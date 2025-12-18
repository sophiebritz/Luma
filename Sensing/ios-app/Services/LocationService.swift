//
//  LocationService.swift
//  NavHalo Pilot
//
//  GPS tracking for speed and weather location
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0.0  // m/s
    @Published var isAuthorized: Bool = false
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0  // Update every 5 meters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        
        checkAuthorization()
    }
    
    func checkAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            startTracking()
        case .denied, .restricted:
            isAuthorized = false
            print("⚠️ Location access denied")
        @unknown default:
            break
        }
    }
    
    func startTracking() {
        guard isAuthorized else {
            print("⚠️ Cannot start location tracking - not authorized")
            return
        }
        
        locationManager.startUpdatingLocation()
        print("📍 GPS tracking started")
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        print("📍 GPS tracking stopped")
    }
    
    // Convert m/s to km/h
    var speedKmh: Double {
        currentSpeed * 3.6
    }
    
    // Classify speed into bins
    var speedEstimate: SpeedEstimate {
        let kmh = speedKmh
        
        if kmh < 1.0 {
            return .stopped
        } else if kmh < 10.0 {
            return .slow
        } else if kmh < 20.0 {
            return .moderate
        } else {
            return .fast
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        // Update speed (negative speed indicates invalid reading)
        if location.speed >= 0 {
            currentSpeed = location.speed
        }
        
        // Debug output (throttled)
        static var lastLog: Date = Date()
        if Date().timeIntervalSince(lastLog) > 2.0 {
            print("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("🏃 Speed: \(String(format: "%.1f", speedKmh)) km/h (\(speedEstimate.rawValue))")
            lastLog = Date()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
}
