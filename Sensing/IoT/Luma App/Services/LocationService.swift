//
//  LocationService.swift
//  LumaHelmet
//
//  CoreLocation service with proper ride tracking callbacks - iOS 17+
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    // Published state
    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0 // m/s
    @Published var currentHeading: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var trackingMode: TrackingMode = .off
    
    enum TrackingMode {
        case off
        case logging      // Low power for ride tracking
        case navigation   // High accuracy for turn-by-turn
    }
    
    // Location manager
    private let locationManager = CLLocationManager()
    
    // Pending mode to resume after authorization is granted
    private var pendingRequestedMode: TrackingMode?
    
    // Location history for ride tracking
    private(set) var locationHistory: [CLLocation] = []
    
    // Callback for location updates - used by RideService
    var onLocationUpdate: ((CLLocation) -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
    }
    
    // MARK: - Authorization
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func isAuthorized(_ status: CLAuthorizationStatus? = nil) -> Bool {
        let s = status ?? locationManager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }
    
    // MARK: - Tracking Control
    func startLoggingMode() {
        if !isAuthorized() {
            // Remember intent and request auth
            pendingRequestedMode = .logging
            requestAuthorization()
            return
        }
        
        // Balanced accuracy for cycling, better speed responsiveness
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 7 // between 5 and 10 meters
        locationManager.startUpdatingLocation()
        
        isTracking = true
        trackingMode = .logging
        print("Location: Started logging mode")
    }
    
    func startNavigationMode() {
        if !isAuthorized() {
            // Remember intent and request auth
            pendingRequestedMode = .navigation
            requestAuthorization()
            return
        }
        
        // High-accuracy mode for turn-by-turn navigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5 // Update every ~5 meters
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        isTracking = true
        trackingMode = .navigation
        print("Location: Started navigation mode")
    }
    
    func upgradeToNavigationMode() {
        // Upgrade from logging to navigation without stopping tracking
        if trackingMode == .logging {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = 5
            locationManager.startUpdatingHeading()
            trackingMode = .navigation
            print("Location: Upgraded to navigation mode")
        } else if trackingMode == .off {
            // If off (e.g., due to pending auth earlier), start nav mode now if authorized
            startNavigationMode()
        }
    }
    
    func downgradeToLoggingMode() {
        // Downgrade from navigation to logging
        if trackingMode == .navigation {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 7
            locationManager.stopUpdatingHeading()
            trackingMode = .logging
            print("Location: Downgraded to logging mode")
        }
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isTracking = false
        trackingMode = .off
        print("Location: Stopped tracking")
    }
    
    // MARK: - Ride Session Management
    func startNewRide() {
        locationHistory.removeAll()
        if trackingMode == .off {
            startLoggingMode()
        }
    }
    
    func endRide() -> [CLLocation] {
        let history = locationHistory
        locationHistory.removeAll()
        // Don't stop tracking here - let the caller decide
        return history
    }
    
    func clearHistory() {
        locationHistory.removeAll()
    }
    
    // MARK: - Distance Calculations
    func distanceTo(_ coordinate: CLLocationCoordinate2D) -> Double {
        guard let current = currentLocation else { return Double.infinity }
        let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return current.distance(from: destination)
    }
    
    /// Haversine formula for accurate distance calculation
    static func haversineDistance(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let R = 6371000.0 // Earth's radius in meters
        
        let lat1 = coord1.latitude * .pi / 180
        let lat2 = coord2.latitude * .pi / 180
        let dLat = (coord2.latitude - coord1.latitude) * .pi / 180
        let dLon = (coord2.longitude - coord1.longitude) * .pi / 180
        
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    }
    
    /// Calculate total distance from location history
    func calculateTotalDistance() -> Double {
        guard locationHistory.count > 1 else { return 0 }
        
        var total: Double = 0
        for i in 1..<locationHistory.count {
            total += locationHistory[i].distance(from: locationHistory[i-1])
        }
        return total
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out inaccurate readings
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentLocation = location
            self.currentSpeed = max(0, location.speed)
            
            // Add to history if tracking
            if self.isTracking {
                self.locationHistory.append(location)
            }
            
            // Call the callback for ride service
            self.onLocationUpdate?(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            
            // If we were waiting for authorization to start a mode, start it now
            if self.isAuthorized(manager.authorizationStatus), let pending = self.pendingRequestedMode {
                self.pendingRequestedMode = nil
                switch pending {
                case .logging:
                    self.startLoggingMode()
                case .navigation:
                    self.startNavigationMode()
                case .off:
                    break
                }
                return
            }
            
            // Backward compatibility: if authorized and tracking was intended
            if self.isAuthorized(manager.authorizationStatus) {
                if self.trackingMode == .off && self.isTracking {
                    // If some caller set isTracking earlier, resume logging
                    self.startLoggingMode()
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
