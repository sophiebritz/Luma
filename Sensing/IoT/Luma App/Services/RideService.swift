//
//  RideService.swift
//  LumaHelmet
//
//  Ride tracking, safety score, analytics with map support - iOS 17+
//

import Foundation
import CoreLocation
import Combine

// MARK: - Ride Session Model
struct RideSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var distance: Double // meters
    var avgSpeed: Double // m/s
    var maxSpeed: Double // m/s
    var brakeCount: Int
    var crashCount: Int
    var bumpCount: Int
    var safetyScore: Int
    var weatherState: String
    var routeCoordinates: [CodableCoordinate] // For map display
    var events: [CodableEvent]
    
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    
    var durationFormatted: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
    
    var distanceFormatted: String {
        if distance < 1000 {
            return "\(Int(distance))m"
        }
        return String(format: "%.1f km", distance / 1000)
    }
    
    var avgSpeedKmh: Double {
        avgSpeed * 3.6
    }
    
    var maxSpeedKmh: Double {
        maxSpeed * 3.6
    }
}

// Codable coordinate for storage
struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speed: Double
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.speed = max(0, location.speed)
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// Codable event for storage
struct CodableEvent: Codable, Identifiable {
    let id: UUID
    let eventClass: EventClass
    let confidence: Float
    let timestamp: Date
    
    init(from event: DetectedEvent) {
        self.id = event.id
        self.eventClass = event.eventClass
        self.confidence = event.confidence
        self.timestamp = event.timestamp
    }
}

// Safety score band
enum SafetyBand: String {
    case safe = "Safe"
    case moderate = "Moderate"
    case highRisk = "High Risk"
    
    var colorName: String {
        switch self {
        case .safe: return "green"
        case .moderate: return "orange"
        case .highRisk: return "red"
        }
    }
    
    static func from(score: Int) -> SafetyBand {
        if score >= 80 { return .safe }
        if score >= 50 { return .moderate }
        return .highRisk
    }
}

// MARK: - Ride Service
class RideService: ObservableObject {
    // Published state
    @Published var currentSession: RideSession?
    @Published var isRiding = false
    @Published var rideHistory: [RideSession] = []
    @Published var currentSafetyScore: Int = 100
    @Published var liveSpeed: Double = 0 // m/s
    @Published var liveMaxSpeed: Double = 0 // m/s
    @Published var liveAvgSpeed: Double = 0 // m/s
    @Published var liveDistance: Double = 0 // meters
    
    // Location service reference
    private weak var locationService: LocationService?
    
    // Tracking data
    private var locationHistory: [CLLocation] = []
    private var speedReadings: [Double] = []
    private var accelerationVariances: [Double] = []
    private var sessionEvents: [DetectedEvent] = []
    
    // InfluxDB configuration (hard-coded only)
    @Published var influxConfigured = true
    
    // Safety score weights
    private let crashPenalty = 50
    private let brakeWeight = 15.0
    private let smoothnessWeight = 15.0
    
    // MARK: - InfluxDB hard-coded config
    private let defaultInfluxURL = "https://us-east-1-1.aws.cloud2.influxdata.com"
    private let defaultInfluxToken = "YgDBMa_F6Z9F6mItk-QB0U0r3xVnNXeVGH7wSC15QnLPP9LTIupU8ZYz-fR44GFGsMTvLzkNQ8Kw2KSmleekZg=="
    private let defaultInfluxOrg = "NavHalo Pilot"
    private let defaultInfluxBucket = "Luma"
    
    init(locationService: LocationService? = nil) {
        self.locationService = locationService
        loadRideHistory()
    }
    
    // MARK: - Ride Control
    func startRide(weatherState: String = "Dry") {
        let session = RideSession(
            id: UUID(),
            startTime: Date(),
            endTime: nil,
            distance: 0,
            avgSpeed: 0,
            maxSpeed: 0,
            brakeCount: 0,
            crashCount: 0,
            bumpCount: 0,
            safetyScore: 100,
            weatherState: weatherState,
            routeCoordinates: [],
            events: []
        )
        
        currentSession = session
        isRiding = true
        locationHistory.removeAll()
        speedReadings.removeAll()
        accelerationVariances.removeAll()
        sessionEvents.removeAll()
        currentSafetyScore = 100
        liveSpeed = 0
        liveMaxSpeed = 0
        liveAvgSpeed = 0
        liveDistance = 0
        
        // Start location tracking if available
        locationService?.startNewRide()
        
        print("Ride: Started session \(session.id)")
    }
    
    func endRide() -> RideSession? {
        guard var session = currentSession else { return nil }
        
        session.endTime = Date()
        
        // Finalize route coordinates
        session.routeCoordinates = locationHistory.map { CodableCoordinate(from: $0) }
        
        // Finalize events
        session.events = sessionEvents.map { CodableEvent(from: $0) }
        
        // Finalize stats
        session.distance = liveDistance
        session.avgSpeed = liveAvgSpeed
        session.maxSpeed = liveMaxSpeed
        session.safetyScore = calculateFinalSafetyScore(session)
        
        // Save to history
        rideHistory.insert(session, at: 0)
        saveRideHistory()
        
        // Upload full journey to InfluxDB (summary + samples + events)
        uploadFullJourneyToInfluxDB(session)
        
        // Reset state
        currentSession = nil
        isRiding = false
        
        print("Ride: Ended session - Score: \(session.safetyScore)")
        return session
    }
    
    func cancelRide() {
        currentSession = nil
        isRiding = false
        locationHistory.removeAll()
        speedReadings.removeAll()
        sessionEvents.removeAll()
        locationService?.clearHistory()
    }
    
    // MARK: - Location Updates (called from LocationService callback)
    func updateLocation(_ location: CLLocation) {
        guard isRiding else { return }
        
        // Update live stats
        let speed = max(0, location.speed)
        liveSpeed = speed
        
        if speed > liveMaxSpeed {
            liveMaxSpeed = speed
        }
        
        speedReadings.append(speed)
        liveAvgSpeed = speedReadings.reduce(0, +) / Double(speedReadings.count)
        
        // Calculate distance from last point
        if let lastLocation = locationHistory.last {
            let delta = location.distance(from: lastLocation)
            // Filter out GPS jumps (> 100m at once is likely an error)
            if delta < 100 {
                liveDistance += delta
            }
        }
        
        locationHistory.append(location)
        
        // Update session
        if var session = currentSession {
            session.distance = liveDistance
            session.avgSpeed = liveAvgSpeed
            session.maxSpeed = liveMaxSpeed
            currentSession = session
        }
    }
    
    // MARK: - Event Recording
    func recordEvent(_ event: DetectedEvent) {
        guard isRiding else { return }
        
        sessionEvents.append(event)
        
        if var session = currentSession {
            switch event.eventClass {
            case .brake:
                session.brakeCount += 1
            case .crash:
                session.crashCount += 1
            case .bump:
                session.bumpCount += 1
            default:
                break
            }
            currentSession = session
            currentSafetyScore = calculateLiveSafetyScore(session)
        }
    }
    
    // MARK: - Safety Score Calculation
    private func calculateLiveSafetyScore(_ session: RideSession) -> Int {
        var score = 100.0
        
        // Crash penalty
        if session.crashCount > 0 {
            score -= Double(min(100, crashPenalty * session.crashCount))
        }
        
        // Braking penalty (normalized by distance)
        let distanceKm = max(0.1, liveDistance / 1000)
        let brakesPerKm = Double(session.brakeCount) / distanceKm
        score -= min(30, brakeWeight * brakesPerKm)
        
        return max(0, min(100, Int(score)))
    }
    
    private func calculateFinalSafetyScore(_ session: RideSession) -> Int {
        var score = 100.0
        
        // Crash penalty
        if session.crashCount > 0 {
            score -= Double(min(100, crashPenalty * session.crashCount))
        }
        
        // Braking penalty
        let distanceKm = max(0.1, session.distance / 1000)
        let brakesPerKm = Double(session.brakeCount) / distanceKm
        score -= min(30, brakeWeight * brakesPerKm)
        
        // Weather adjustment (give credit for bad conditions)
        switch session.weatherState {
        case "Wet": score += 5
        case "Icy": score += 10
        default: break
        }
        
        return max(0, min(100, Int(score)))
    }
    
    var safetyBand: SafetyBand {
        SafetyBand.from(score: currentSafetyScore)
    }
    
    // MARK: - InfluxDB Integration (Full journey upload with hardcoded config)
    private func uploadFullJourneyToInfluxDB(_ session: RideSession) {
        // Always use hard-coded defaults
        let url = defaultInfluxURL
        let token = defaultInfluxToken
        let org = defaultInfluxOrg
        let bucket = defaultInfluxBucket
        
        guard !url.isEmpty, !token.isEmpty, !org.isEmpty, !bucket.isEmpty else {
            print("InfluxDB: Not configured (missing URL/token/org/bucket)")
            return
        }
        
        let rideID = session.id.uuidString
        var lines: [String] = []
        
        // 1) Summary measurement (rides)
        let summaryMeasurement = "rides"
        let summaryTags = "ride_id=\(rideID),weather_state=\(escapeTag(session.weatherState))"
        let summaryFields = [
            "distance=\(session.distance)",
            "avg_speed=\(session.avgSpeed)",
            "max_speed=\(session.maxSpeed)",
            "duration=\(session.duration)",
            "brake_count=\(session.brakeCount)i",
            "crash_count=\(session.crashCount)i",
            "safety_score=\(session.safetyScore)i"
        ].joined(separator: ",")
        let summaryTs = toNs(session.startTime)
        lines.append("\(summaryMeasurement),\(summaryTags) \(summaryFields) \(summaryTs)")
        
        // 2) Route samples (ride_points)
        let pointsMeasurement = "ride_points"
        for coord in session.routeCoordinates {
            let tags = "ride_id=\(rideID)"
            let fields = "lat=\(coord.latitude),lon=\(coord.longitude),speed=\(coord.speed)"
            let ts = toNs(coord.timestamp)
            lines.append("\(pointsMeasurement),\(tags) \(fields) \(ts)")
        }
        
        // 3) Events (ride_events)
        let eventsMeasurement = "ride_events"
        for ev in session.events {
            let tags = "ride_id=\(rideID),class=\(escapeTag(ev.eventClass.name))"
            let fields = "confidence=\(ev.confidence)"
            let ts = toNs(ev.timestamp)
            lines.append("\(eventsMeasurement),\(tags) \(fields) \(ts)")
        }
        
        let batch = lines.joined(separator: "\n")
        sendToInfluxDB(batch, url: url, token: token, org: org, bucket: bucket)
    }
    
    private func toNs(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1_000_000_000)
    }
    
    private func escapeTag(_ value: String) -> String {
        // Influx tag values: escape commas, spaces, and equals
        value
            .replacingOccurrences(of: " ", with: "\\ ")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "=", with: "\\=")
    }
    
    private func sendToInfluxDB(_ lineProtocol: String, url: String, token: String, org: String, bucket: String) {
        let orgEncoded = org.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? org
        let bucketEncoded = bucket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bucket
        guard let requestURL = URL(string: "\(url)/api/v2/write?org=\(orgEncoded)&bucket=\(bucketEncoded)&precision=ns") else {
            print("InfluxDB: Invalid URL")
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = lineProtocol.data(using: .utf8)
        
        // Debug log
        print("InfluxDB: POST \(requestURL.absoluteString)")
        print("InfluxDB: payload lines=\(lineProtocol.components(separatedBy: "\n").count)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("InfluxDB error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 {
                    print("InfluxDB: Upload successful")
                } else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(no body)"
                    print("InfluxDB: Status \(httpResponse.statusCode) body: \(body)")
                }
            } else {
                print("InfluxDB: No HTTP response")
            }
        }.resume()
    }
    
    // MARK: - Persistence
    private func saveRideHistory() {
        // Keep only last 50 rides
        let toSave = Array(rideHistory.prefix(50))
        if let encoded = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(encoded, forKey: "rideHistory")
        }
    }
    
    private func loadRideHistory() {
        if let data = UserDefaults.standard.data(forKey: "rideHistory"),
           let decoded = try? JSONDecoder().decode([RideSession].self, from: data) {
            rideHistory = decoded
        }
    }
    
    func deleteRide(_ session: RideSession) {
        rideHistory.removeAll { $0.id == session.id }
        saveRideHistory()
    }
    
    func clearAllHistory() {
        rideHistory.removeAll()
        saveRideHistory()
    }
    
    // MARK: - Statistics
    var totalRides: Int { rideHistory.count }
    
    var totalDistance: Double {
        rideHistory.reduce(0) { $0 + $1.distance }
    }
    
    var averageSafetyScore: Int {
        guard !rideHistory.isEmpty else { return 0 }
        return rideHistory.reduce(0) { $0 + $1.safetyScore } / rideHistory.count
    }
    
    var bestSafetyScore: Int {
        rideHistory.map { $0.safetyScore }.max() ?? 0
    }
    
    var totalRideTime: TimeInterval {
        rideHistory.reduce(0) { $0 + $1.duration }
    }
}

