//
//  RideTracker.swift
//  SmartHelmetApp
//
//  Tracks ride telemetry and stores locally + publishes to InfluxDB
//

import Foundation
import CoreLocation
import Combine

class RideTracker: NSObject, ObservableObject {
    static let shared = RideTracker()
    
    // MARK: - Published Properties
    @Published var isTracking = false
    @Published var currentRide: RideSession?
    @Published var rideHistory: [RideSession] = []
    @Published var currentSpeed: Double = 0  // km/h
    @Published var currentDistance: Double = 0  // meters
    @Published var currentDuration: TimeInterval = 0
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var startTime: Date?
    private var timer: Timer?
    private var dataPoints: [RideDataPoint] = []
    
    // References
    weak var bluetoothManager: BluetoothManager?
    private let influxDB = InfluxDBService.shared
    
    // Tracking state
    private var wasLeftTurnActive = false
    private var wasRightTurnActive = false
    private var wasBraking = false
    
    private let historyKey = "ride_history"
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        loadHistory()
    }
    
    // MARK: - Ride Control
    
    func startRide(helmetId: String? = nil) {
        guard !isTracking else { return }
        
        var ride = RideSession()
        ride.helmetId = helmetId ?? bluetoothManager?.helmetPeripheral?.identifier.uuidString
        
        currentRide = ride
        isTracking = true
        startTime = Date()
        currentSpeed = 0
        currentDistance = 0
        currentDuration = 0
        dataPoints.removeAll()
        lastLocation = nil
        
        // Reset counters
        wasLeftTurnActive = false
        wasRightTurnActive = false
        wasBraking = false
        
        // Start location updates
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // Start timer for duration
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        
        print("ðŸš´ Ride started")
    }
    
    func stopRide() {
        guard isTracking else { return }
        
        isTracking = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        
        // Finalize ride
        if var ride = currentRide {
            ride.endTime = Date()
            ride.duration = currentDuration
            ride.distance = currentDistance
            ride.averageSpeed = currentDuration > 0 ? (currentDistance / 1000) / (currentDuration / 3600) : 0
            ride.endLatitude = lastLocation?.coordinate.latitude
            ride.endLongitude = lastLocation?.coordinate.longitude
            
            // Reverse geocode end location
            if let location = lastLocation {
                geocodeLocation(location) { [weak self] name in
                    self?.currentRide?.endLocationName = name
                    self?.finalizeRide()
                }
            } else {
                finalizeRide()
            }
            
            currentRide = ride
        }
        
        // Flush any remaining data to InfluxDB
        influxDB.flushBuffer()
        
        print("ðŸš´ Ride stopped: \(formatDistance(currentDistance)), \(formatDuration(currentDuration))")
    }
    
    private func finalizeRide() {
        guard var ride = currentRide else { return }
        
        ride.endTime = Date()
        ride.duration = currentDuration
        ride.distance = currentDistance
        ride.averageSpeed = currentDuration > 0 ? (currentDistance / 1000) / (currentDuration / 3600) : 0
        
        // Save to history
        rideHistory.insert(ride, at: 0)
        saveHistory()
        
        currentRide = ride
        
        // Auto-upload if configured
        if influxDB.isConfigured {
            Task {
                await influxDB.uploadRide(ride)
            }
        }
    }
    
    private func updateDuration() {
        guard let start = startTime else { return }
        currentDuration = Date().timeIntervalSince(start)
        currentRide?.duration = currentDuration
    }
    
    // MARK: - Data Recording
    
    private func recordDataPoint(location: CLLocation) {
        guard isTracking, let ride = currentRide else { return }
        
        var point = RideDataPoint(
            timestamp: Date(),
            rideId: ride.id.uuidString,
            helmetId: ride.helmetId ?? "unknown",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        
        point.altitude = location.altitude
        point.speed = location.speed >= 0 ? location.speed : nil
        point.heading = location.course >= 0 ? location.course : nil
        
        // Get helmet state
        if let bluetooth = bluetoothManager {
            let state = bluetooth.sensorData.state
            point.helmetState = state.stringValue
            point.helmetBattery = bluetooth.sensorData.batteryLevel
            
            // Check for events
            let isLeftTurn = state == .turnLeft
            let isRightTurn = state == .turnRight
            let isBraking = state == .braking
            
            point.turnLeftActive = isLeftTurn
            point.turnRightActive = isRightTurn
            point.brakingActive = isBraking
            point.crashAlert = state == .crashAlert
            
            // Count transitions (not continuous states)
            if isLeftTurn && !wasLeftTurnActive {
                currentRide?.turnLeftCount += 1
            }
            if isRightTurn && !wasRightTurnActive {
                currentRide?.turnRightCount += 1
            }
            if isBraking && !wasBraking {
                currentRide?.brakeCount += 1
            }
            if state == .crashAlert {
                currentRide?.crashAlerts += 1
            }
            
            wasLeftTurnActive = isLeftTurn
            wasRightTurnActive = isRightTurn
            wasBraking = isBraking
            
            // IMU data if available
            point.accelerationX = bluetooth.sensorData.accelerationX
            point.accelerationY = bluetooth.sensorData.accelerationY
            point.accelerationZ = bluetooth.sensorData.accelerationZ
        }
        
        // Store locally
        dataPoints.append(point)
        
        // Send to InfluxDB
        influxDB.recordDataPoint(point)
    }
    
    // MARK: - History Management
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(rideHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([RideSession].self, from: data) {
            rideHistory = decoded
        }
    }
    
    func deleteRide(at indexSet: IndexSet) {
        rideHistory.remove(atOffsets: indexSet)
        saveHistory()
    }
    
    func clearHistory() {
        rideHistory.removeAll()
        saveHistory()
    }
    
    // MARK: - Upload to Cloud
    
    func uploadRide(_ ride: RideSession) async -> Bool {
        let success = await influxDB.uploadRide(ride)
        
        if success {
            // Mark as uploaded
            if let index = rideHistory.firstIndex(where: { $0.id == ride.id }) {
                await MainActor.run {
                    rideHistory[index].uploadedToCloud = true
                    saveHistory()
                }
            }
        }
        
        return success
    }
    
    func uploadAllRides() async -> Int {
        var successCount = 0
        
        for ride in rideHistory where !ride.uploadedToCloud {
            if await uploadRide(ride) {
                successCount += 1
            }
        }
        
        return successCount
    }
    
    // MARK: - Helpers
    
    private func geocodeLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            let name = placemarks?.first?.locality ?? placemarks?.first?.name
            completion(name)
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Location Manager Delegate

extension RideTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let location = locations.last else { return }
        
        // Update speed
        if location.speed >= 0 {
            currentSpeed = location.speed * 3.6  // m/s to km/h
            
            // Track max speed
            if currentSpeed > (currentRide?.maxSpeed ?? 0) {
                currentRide?.maxSpeed = currentSpeed
            }
        }
        
        // Update distance
        if let lastLoc = lastLocation {
            let delta = location.distance(from: lastLoc)
            // Filter out GPS noise (ignore jumps > 100m)
            if delta < 100 {
                currentDistance += delta
            }
        } else {
            // First location - set start location
            currentRide?.startLatitude = location.coordinate.latitude
            currentRide?.startLongitude = location.coordinate.longitude
            
            // Reverse geocode start location
            geocodeLocation(location) { [weak self] name in
                self?.currentRide?.startLocationName = name
            }
        }
        
        lastLocation = location
        
        // Record data point
        recordDataPoint(location: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}
