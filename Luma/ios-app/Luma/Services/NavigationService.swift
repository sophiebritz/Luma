//
//  NavigationService.swift
//  SmartHelmetApp
//
//  Handles navigation and auto-indication for turn signals
//

import Foundation
import MapKit
import CoreLocation
import Combine

class NavigationService: NSObject, ObservableObject {
    // Published properties
    @Published var isNavigating = false
    @Published var currentRoute: MKRoute?
    @Published var currentStepIndex = 0
    @Published var currentInstruction: String = ""
    @Published var distanceToNextTurn: CLLocationDistance = 0
    @Published var nextTurnDirection: TurnDirection?
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var totalDistanceRemaining: CLLocationDistance = 0
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var autoIndicateEnabled = true
    
    // Current location
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    
    // Turn signal state
    @Published var autoIndicateActive = false
    @Published var currentAutoTurn: TurnDirection?
    
    // Location manager
    private let locationManager = CLLocationManager()
    
    // Bluetooth manager reference (set from outside)
    weak var bluetoothManager: BluetoothManager?
    
    // Thresholds
    private let turnWarningDistance: CLLocationDistance = 100 // meters before turn to activate signal
    private let turnCompleteDistance: CLLocationDistance = 20 // meters after turn to deactivate
    private let arrivedThreshold: CLLocationDistance = 30 // meters to consider arrived
    
    // Route steps
    private var routeSteps: [MKRoute.Step] = []
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Start low accuracy
        locationManager.distanceFilter = 50 // Start with less frequent updates
        locationManager.headingFilter = 10
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation() // Get initial location
    }
    
    private func enableHighAccuracyTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.headingFilter = 5
        locationManager.startUpdatingHeading()
    }
    
    private func disableHighAccuracyTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - Search
    
    func searchPlaces(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        if let location = currentLocation {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50000,
                longitudinalMeters: 50000
            )
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                self?.searchResults = response?.mapItems ?? []
            }
        }
    }
    
    // MARK: - Route Calculation
    
    func calculateRoute(to destination: MKMapItem) {
        guard let currentLocation = currentLocation else {
            errorMessage = "Current location not available"
            return
        }
        
        let request = MKDirections.Request()
        let sourcePlacemark = MKPlacemark(coordinate: currentLocation.coordinate)
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = destination
        request.transportType = .automobile // Better for road routes than walking
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let route = response?.routes.first else {
                    self?.errorMessage = "No route found"
                    return
                }
                
                // Store route for preview - don't auto-start
                self?.currentRoute = route
                self?.routeSteps = route.steps
                
                // Log steps for debugging
                print("ðŸ—ºï¸ Route calculated: \(route.steps.count) steps, \(Int(route.distance))m")
                for (index, step) in route.steps.enumerated() {
                    let turnDir = self?.parseTurnDirection(from: step.instructions)
                    print("   Step \(index): \(step.instructions) â†’ \(turnDir?.title ?? "STRAIGHT")")
                }
            }
        }
    }
    
    func calculateRoute(to coordinate: CLLocationCoordinate2D, name: String = "Destination") {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        calculateRoute(to: mapItem)
    }
    
    // MARK: - Test Functions
    
    /// Test auto-indication without navigation - for debugging
    func testAutoIndicate(direction: TurnDirection) {
        guard let bluetooth = bluetoothManager, bluetooth.isConnected else {
            print("âŒ TEST: Helmet not connected!")
            return
        }
        
        print("ðŸ§ª TEST: Activating \(direction.title) signal for 5 seconds...")
        
        switch direction {
        case .left:
            bluetooth.turnLeftOn()
        case .right:
            bluetooth.turnRightOn()
        }
        
        // Turn off after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            print("ðŸ§ª TEST: Deactivating signal")
            switch direction {
            case .left:
                bluetooth.turnLeftOff()
            case .right:
                bluetooth.turnRightOff()
            }
        }
    }
    
    // MARK: - Navigation Control
    
    func startNavigation(with route: MKRoute) {
        currentRoute = route
        routeSteps = route.steps
        currentStepIndex = 0
        isNavigating = true
        
        // Reset auto-indication tracking
        activeSignalForStep = -1
        activeSignalDirection = nil
        turnPointLocation = nil
        
        // Enable high accuracy tracking for navigation
        enableHighAccuracyTracking()
        
        // Start ride tracking
        RideTracker.shared.bluetoothManager = bluetoothManager
        RideTracker.shared.startRide(helmetId: bluetoothManager?.helmetPeripheral?.identifier.uuidString)
        
        // Update initial instruction
        updateCurrentStep()
        
        // Log route steps for debugging
        print("ðŸ—ºï¸ Navigation started: \(route.steps.count) steps, \(Int(route.distance))m total")
        for (index, step) in route.steps.enumerated() {
            let turnDir = parseTurnDirection(from: step.instructions)
            print("   Step \(index): \(step.instructions) â†’ \(turnDir?.title ?? "STRAIGHT")")
        }
    }
    
    func stopNavigation() {
        isNavigating = false
        currentRoute = nil
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = ""
        nextTurnDirection = nil
        
        // Reset auto-indication tracking
        activeSignalForStep = -1
        activeSignalDirection = nil
        turnPointLocation = nil
        
        // Stop auto-indicate if active
        deactivateAutoIndicate()
        
        // Stop ride tracking
        RideTracker.shared.stopRide()
        
        // Return to low accuracy tracking
        disableHighAccuracyTracking()
        
        print("ðŸ—ºï¸ Navigation stopped")
    }
    
    // MARK: - Navigation Updates
    
    private var lastLogTime: Date = Date.distantPast
    
    private func updateNavigation(with location: CLLocation) {
        guard isNavigating, !routeSteps.isEmpty else { return }
        
        // Check if we've arrived at destination
        if let lastStep = routeSteps.last {
            let distanceToDestination = location.distance(from: CLLocation(
                latitude: lastStep.polyline.coordinate.latitude,
                longitude: lastStep.polyline.coordinate.longitude
            ))
            
            if distanceToDestination < arrivedThreshold {
                arrivedAtDestination()
                return
            }
            
            totalDistanceRemaining = distanceToDestination
        }
        
        // Find current step
        updateCurrentStepBasedOnLocation(location)
        
        // Update distance to next turn
        if currentStepIndex < routeSteps.count {
            let currentStep = routeSteps[currentStepIndex]
            let stepEndLocation = CLLocation(
                latitude: currentStep.polyline.coordinate.latitude,
                longitude: currentStep.polyline.coordinate.longitude
            )
            distanceToNextTurn = location.distance(from: stepEndLocation)
            
            // Debug log every 3 seconds
            if Date().timeIntervalSince(lastLogTime) > 3 {
                lastLogTime = Date()
                let turnStr = nextTurnDirection?.title ?? "NONE"
                let signalStr = autoIndicateActive ? "ON(\(currentAutoTurn?.title ?? "?"))" : "OFF"
                print("ðŸ“ Step \(currentStepIndex+1)/\(routeSteps.count) | Dist: \(Int(distanceToNextTurn))m | Turn: \(turnStr) | Signal: \(signalStr)")
            }
            
            // Handle auto-indication
            handleAutoIndication()
        }
        
        // Update ETA
        if let route = currentRoute {
            let progress = 1.0 - (totalDistanceRemaining / route.distance)
            estimatedTimeRemaining = route.expectedTravelTime * (1.0 - progress)
        }
    }
    
    private func updateCurrentStepBasedOnLocation(_ location: CLLocation) {
        // Find the closest step we should be on
        for (index, step) in routeSteps.enumerated() {
            if index < currentStepIndex { continue }
            
            let stepLocation = CLLocation(
                latitude: step.polyline.coordinate.latitude,
                longitude: step.polyline.coordinate.longitude
            )
            
            let distance = location.distance(from: stepLocation)
            
            // If we're past this step's end point
            if distance < turnCompleteDistance && index > currentStepIndex {
                currentStepIndex = index
                updateCurrentStep()
                break
            }
        }
    }
    
    private func updateCurrentStep() {
        guard currentStepIndex < routeSteps.count else { return }
        
        let step = routeSteps[currentStepIndex]
        currentInstruction = step.instructions
        
        // Determine turn direction from instruction
        nextTurnDirection = parseTurnDirection(from: step.instructions)
        
        print("Step \(currentStepIndex + 1)/\(routeSteps.count): \(step.instructions)")
    }
    
    private func parseTurnDirection(from instruction: String) -> TurnDirection? {
        let lowercased = instruction.lowercased()
        
        if lowercased.contains("turn left") || 
           lowercased.contains("slight left") ||
           lowercased.contains("sharp left") ||
           lowercased.contains("bear left") {
            return .left
        }
        
        if lowercased.contains("turn right") ||
           lowercased.contains("slight right") ||
           lowercased.contains("sharp right") ||
           lowercased.contains("bear right") {
            return .right
        }
        
        // Check for roundabout exits
        if lowercased.contains("exit") {
            if lowercased.contains("left") { return .left }
            if lowercased.contains("right") { return .right }
        }
        
        return nil
    }
    
    // MARK: - Auto-Indication
    
    // Track the turn we're currently signaling for
    private var activeSignalForStep: Int = -1
    private var activeSignalDirection: TurnDirection?
    private var turnPointLocation: CLLocation?
    
    private func handleAutoIndication() {
        guard autoIndicateEnabled, isNavigating else {
            if autoIndicateActive {
                deactivateAutoIndicate()
            }
            return
        }
        
        // If we already have an active signal, check if we should deactivate
        if autoIndicateActive, let turnPoint = turnPointLocation, let currentLoc = currentLocation {
            let distanceFromTurnPoint = currentLoc.distance(from: turnPoint)
            
            // Deactivate when we're past the turn point by 20m
            if distanceFromTurnPoint < turnCompleteDistance && currentStepIndex > activeSignalForStep {
                print("ðŸ”¶ Turn completed - deactivating signal")
                deactivateAutoIndicate()
                return
            }
            
            // Keep signal active - don't do anything else
            return
        }
        
        // Check if we should activate a new signal
        if let direction = nextTurnDirection,
           distanceToNextTurn <= turnWarningDistance,
           distanceToNextTurn > 0,
           !autoIndicateActive {
            
            // Store the turn point location for this step
            if currentStepIndex < routeSteps.count {
                let step = routeSteps[currentStepIndex]
                turnPointLocation = CLLocation(
                    latitude: step.polyline.coordinate.latitude,
                    longitude: step.polyline.coordinate.longitude
                )
            }
            
            activeSignalForStep = currentStepIndex
            activeSignalDirection = direction
            activateAutoIndicate(direction: direction)
        }
    }
    
    private func activateAutoIndicate(direction: TurnDirection) {
        guard let bluetooth = bluetoothManager else {
            print("âš ï¸ Cannot auto-indicate - no bluetooth manager")
            return
        }
        
        guard bluetooth.isConnected else {
            print("âš ï¸ Cannot auto-indicate - helmet not connected")
            return
        }
        
        autoIndicateActive = true
        currentAutoTurn = direction
        
        // Send command multiple times to ensure it's received
        switch direction {
        case .left:
            bluetooth.turnLeftOn()
            print("ðŸ”¶ AUTO-INDICATE LEFT ON at \(Int(distanceToNextTurn))m from turn")
        case .right:
            bluetooth.turnRightOn()
            print("ðŸ”¶ AUTO-INDICATE RIGHT ON at \(Int(distanceToNextTurn))m from turn")
        }
        
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        #endif
    }
    
    private func deactivateAutoIndicate() {
        guard autoIndicateActive else { return }
        
        if let bluetooth = bluetoothManager, let direction = currentAutoTurn ?? activeSignalDirection {
            switch direction {
            case .left:
                bluetooth.turnLeftOff()
                print("ðŸ”¶ AUTO-INDICATE LEFT OFF")
            case .right:
                bluetooth.turnRightOff()
                print("ðŸ”¶ AUTO-INDICATE RIGHT OFF")
            }
        }
        
        autoIndicateActive = false
        currentAutoTurn = nil
        activeSignalDirection = nil
        turnPointLocation = nil
        print("ðŸ”¶ Auto-indicate deactivated")
    }
    
    private func arrivedAtDestination() {
        print("ðŸŽ‰ Arrived at destination!")
        
        // Haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        
        stopNavigation()
    }
}

// MARK: - CLLocationManagerDelegate

extension NavigationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        if isNavigating {
            updateNavigation(with: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enable in Settings."
        default:
            break
        }
    }
}
