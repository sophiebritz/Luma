//
//  InfluxDBService.swift
//  SmartHelmetApp
//
//  Publishes ride telemetry to InfluxDB for time-series storage and analysis
//

import Foundation
import CoreLocation
import Combine

class InfluxDBService: ObservableObject {
    // MARK: - Configuration
    // Replace with your InfluxDB Cloud details
    static let shared = InfluxDBService()
    
    @Published var isConfigured = false
    @Published var lastUploadStatus: String = "Not uploaded"
    @Published var isUploading = false
    
    // InfluxDB Configuration - UPDATE THESE!
    private var influxURL: String = ""      // e.g., "https://eu-central-1-1.aws.cloud2.influxdata.com"
    private var influxOrg: String = ""      // Your org name
    private var influxBucket: String = ""   // e.g., "smart-helmet"
    private var influxToken: String = ""    // API token with write access
    
    // Buffer for batching writes
    private var dataBuffer: [RideDataPoint] = []
    private let bufferSize = 50  // Send in batches of 50
    
    private init() {
        loadConfiguration()
    }
    
    // MARK: - Configuration
    
    func configure(url: String, org: String, bucket: String, token: String) {
        self.influxURL = url
        self.influxOrg = org
        self.influxBucket = bucket
        self.influxToken = token
        self.isConfigured = !url.isEmpty && !token.isEmpty
        saveConfiguration()
    }
    
    private func saveConfiguration() {
        UserDefaults.standard.set(influxURL, forKey: "influx_url")
        UserDefaults.standard.set(influxOrg, forKey: "influx_org")
        UserDefaults.standard.set(influxBucket, forKey: "influx_bucket")
        // Note: In production, use Keychain for token storage
        UserDefaults.standard.set(influxToken, forKey: "influx_token")
    }
    
    private func loadConfiguration() {
        influxURL = UserDefaults.standard.string(forKey: "influx_url") ?? ""
        influxOrg = UserDefaults.standard.string(forKey: "influx_org") ?? ""
        influxBucket = UserDefaults.standard.string(forKey: "influx_bucket") ?? ""
        influxToken = UserDefaults.standard.string(forKey: "influx_token") ?? ""
        isConfigured = !influxURL.isEmpty && !influxToken.isEmpty
    }
    
    // MARK: - Data Point Recording
    
    func recordDataPoint(_ point: RideDataPoint) {
        dataBuffer.append(point)
        
        // Flush when buffer is full
        if dataBuffer.count >= bufferSize {
            flushBuffer()
        }
    }
    
    func flushBuffer() {
        guard !dataBuffer.isEmpty else { return }
        let pointsToSend = dataBuffer
        dataBuffer.removeAll()
        
        Task {
            await sendToInfluxDB(points: pointsToSend)
        }
    }
    
    // MARK: - InfluxDB Line Protocol
    
    private func toLineProtocol(_ point: RideDataPoint) -> String {
        // InfluxDB Line Protocol format:
        // measurement,tag1=value1,tag2=value2 field1=value1,field2=value2 timestamp
        
        var tags = [
            "ride_id=\(point.rideId)",
            "helmet_id=\(point.helmetId)"
        ]
        
        if let state = point.helmetState {
            tags.append("helmet_state=\(state)")
        }
        
        var fields: [String] = []
        
        // Location fields
        fields.append("latitude=\(point.latitude)")
        fields.append("longitude=\(point.longitude)")
        
        if let altitude = point.altitude {
            fields.append("altitude=\(altitude)")
        }
        
        // Speed (convert to km/h for readability)
        if let speed = point.speed, speed >= 0 {
            fields.append("speed=\(speed * 3.6)")  // m/s to km/h
        }
        
        // Heading
        if let heading = point.heading {
            fields.append("heading=\(heading)")
        }
        
        // Acceleration (for crash detection analysis)
        if let accelX = point.accelerationX {
            fields.append("accel_x=\(accelX)")
        }
        if let accelY = point.accelerationY {
            fields.append("accel_y=\(accelY)")
        }
        if let accelZ = point.accelerationZ {
            fields.append("accel_z=\(accelZ)")
        }
        
        // Events (as integer flags)
        fields.append("turn_left=\(point.turnLeftActive ? 1 : 0)i")
        fields.append("turn_right=\(point.turnRightActive ? 1 : 0)i")
        fields.append("braking=\(point.brakingActive ? 1 : 0)i")
        fields.append("crash_alert=\(point.crashAlert ? 1 : 0)i")
        
        // Battery
        if let battery = point.helmetBattery {
            fields.append("helmet_battery=\(battery)i")
        }
        
        // Timestamp in nanoseconds
        let timestamp = Int64(point.timestamp.timeIntervalSince1970 * 1_000_000_000)
        
        return "ride_telemetry,\(tags.joined(separator: ",")) \(fields.joined(separator: ",")) \(timestamp)"
    }
    
    // MARK: - API Communication
    
    private func sendToInfluxDB(points: [RideDataPoint]) async {
        guard isConfigured else {
            print("InfluxDB not configured")
            return
        }
        
        let lineData = points.map { toLineProtocol($0) }.joined(separator: "\n")
        
        guard let url = URL(string: "\(influxURL)/api/v2/write?org=\(influxOrg)&bucket=\(influxBucket)&precision=ns") else {
            print("Invalid InfluxDB URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(influxToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = lineData.data(using: .utf8)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                await MainActor.run {
                    if httpResponse.statusCode == 204 {
                        print("âœ… Sent \(points.count) points to InfluxDB")
                        self.lastUploadStatus = "Uploaded \(points.count) points"
                    } else {
                        print("âŒ InfluxDB error: \(httpResponse.statusCode)")
                        self.lastUploadStatus = "Error: \(httpResponse.statusCode)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                print("âŒ InfluxDB upload failed: \(error)")
                self.lastUploadStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Upload Complete Ride
    
    func uploadRide(_ ride: RideSession) async -> Bool {
        guard isConfigured else {
            await MainActor.run {
                lastUploadStatus = "Not configured"
            }
            return false
        }
        
        await MainActor.run {
            isUploading = true
        }
        
        // Send ride summary
        let summaryLine = rideToLineProtocol(ride)
        
        guard let url = URL(string: "\(influxURL)/api/v2/write?org=\(influxOrg)&bucket=\(influxBucket)&precision=ns") else {
            await MainActor.run {
                isUploading = false
                lastUploadStatus = "Invalid URL"
            }
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(influxToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = summaryLine.data(using: .utf8)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let success = httpResponse.statusCode == 204
                await MainActor.run {
                    isUploading = false
                    lastUploadStatus = success ? "Ride uploaded âœ“" : "Error: \(httpResponse.statusCode)"
                }
                return success
            }
        } catch {
            await MainActor.run {
                isUploading = false
                lastUploadStatus = "Failed: \(error.localizedDescription)"
            }
        }
        
        return false
    }
    
    private func rideToLineProtocol(_ ride: RideSession) -> String {
        let tags = [
            "ride_id=\(ride.id.uuidString)",
            "helmet_id=\(ride.helmetId ?? "unknown")"
        ]
        
        var fields: [String] = [
            "duration=\(ride.duration)",
            "distance=\(ride.distance)",
            "avg_speed=\(ride.averageSpeed)",
            "max_speed=\(ride.maxSpeed)",
            "turn_left_count=\(ride.turnLeftCount)i",
            "turn_right_count=\(ride.turnRightCount)i",
            "brake_count=\(ride.brakeCount)i",
            "crash_alerts=\(ride.crashAlerts)i"
        ]
        
        if let startLat = ride.startLatitude, let startLon = ride.startLongitude {
            fields.append("start_lat=\(startLat)")
            fields.append("start_lon=\(startLon)")
        }
        
        if let endLat = ride.endLatitude, let endLon = ride.endLongitude {
            fields.append("end_lat=\(endLat)")
            fields.append("end_lon=\(endLon)")
        }
        
        let timestamp = Int64(ride.startTime.timeIntervalSince1970 * 1_000_000_000)
        
        return "ride_summary,\(tags.joined(separator: ",")) \(fields.joined(separator: ",")) \(timestamp)"
    }
    
    // MARK: - Query Data (for analysis)
    
    func queryRideData(rideId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard isConfigured else {
            completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not configured"])))
            return
        }
        
        let fluxQuery = """
        from(bucket: "\(influxBucket)")
            |> range(start: -30d)
            |> filter(fn: (r) => r._measurement == "ride_telemetry")
            |> filter(fn: (r) => r.ride_id == "\(rideId)")
            |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
        """
        
        guard let url = URL(string: "\(influxURL)/api/v2/query?org=\(influxOrg)") else {
            completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(influxToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.flux", forHTTPHeaderField: "Content-Type")
        request.setValue("application/csv", forHTTPHeaderField: "Accept")
        request.httpBody = fluxQuery.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let csvString = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            
            // Parse CSV response
            completion(.success(["csv": csvString]))
        }.resume()
    }
}

// MARK: - Data Models

struct RideDataPoint {
    let timestamp: Date
    let rideId: String
    let helmetId: String
    
    // Location
    let latitude: Double
    let longitude: Double
    var altitude: Double?
    var speed: Double?  // m/s
    var heading: Double?
    
    // IMU Data
    var accelerationX: Double?
    var accelerationY: Double?
    var accelerationZ: Double?
    
    // Helmet state
    var helmetState: String?
    var helmetBattery: Int?
    
    // Events
    var turnLeftActive: Bool = false
    var turnRightActive: Bool = false
    var brakingActive: Bool = false
    var crashAlert: Bool = false
}

struct RideSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval = 0
    var distance: Double = 0  // meters
    var averageSpeed: Double = 0  // km/h
    var maxSpeed: Double = 0  // km/h
    
    // Location
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startLocationName: String?
    var endLocationName: String?
    
    // Events
    var turnLeftCount: Int = 0
    var turnRightCount: Int = 0
    var brakeCount: Int = 0
    var crashAlerts: Int = 0
    
    // Helmet
    var helmetId: String?
    
    // Upload status
    var uploadedToCloud: Bool = false
    
    init() {
        self.id = UUID()
        self.startTime = Date()
    }
}
