//
//  NavigationService.swift
//  LumaHelmet
//
//  MapKit-based bicycle routing and instructions - iOS 17+
//

import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Navigation Models
struct RouteInstruction: Identifiable {
    let id = UUID()
    let instruction: String
    let distance: Double // meters
    let duration: Double // seconds (approx for MapKit steps)
    let type: Int // synthetic type used for TurnType mapping
    let coordinate: CLLocationCoordinate2D
    
    var turnType: TurnType {
        TurnType.from(code: type)
    }
    
    var distanceFormatted: String {
        if distance < 100 {
            return "\(Int(distance))m"
        } else if distance < 1000 {
            return "\(Int(distance / 10) * 10)m"
        }
        return String(format: "%.1f km", distance / 1000)
    }
}

enum TurnType: String {
    case left = "Turn Left"
    case right = "Turn Right"
    case slightLeft = "Slight Left"
    case slightRight = "Slight Right"
    case sharpLeft = "Sharp Left"
    case sharpRight = "Sharp Right"
    case straight = "Continue Straight"
    case uturn = "U-Turn"
    case arrive = "Arrive"
    case depart = "Depart"
    case roundaboutLeft = "Roundabout Left"
    case roundaboutRight = "Roundabout Right"
    case unknown = "Continue"
    
    var iconName: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .slightLeft: return "arrow.up.left"
        case .sharpLeft: return "arrow.turn.left.up"
        case .right: return "arrow.turn.up.right"
        case .slightRight: return "arrow.up.right"
        case .sharpRight: return "arrow.turn.right.up"
        case .straight: return "arrow.up"
        case .uturn: return "arrow.uturn.down"
        case .arrive: return "mappin.circle.fill"
        case .depart: return "figure.walk"
        case .roundaboutLeft, .roundaboutRight: return "arrow.triangle.2.circlepath"
        case .unknown: return "arrow.up"
        }
    }
    
    var isLeftTurn: Bool {
        switch self {
        case .left, .slightLeft, .sharpLeft, .roundaboutLeft: return true
        default: return false
        }
    }
    
    var isRightTurn: Bool {
        switch self {
        case .right, .slightRight, .sharpRight, .roundaboutRight: return true
        default: return false
        }
    }
    
    // Map a synthetic type code to TurnType (we’ll synthesize codes from MKRoute.Step text)
    static func from(code: Int) -> TurnType {
        switch code {
        case 0: return .left
        case 1: return .right
        case 2: return .sharpLeft
        case 3: return .sharpRight
        case 4: return .slightLeft
        case 5: return .slightRight
        case 6: return .straight
        case 7: return .roundaboutRight
        case 8: return .roundaboutLeft
        case 9: return .uturn
        case 10: return .arrive
        case 11: return .depart
        default: return .unknown
        }
    }
}

struct Route {
    let coordinates: [CLLocationCoordinate2D]
    let instructions: [RouteInstruction]
    let totalDistance: Double // meters
    let totalDuration: Double // seconds
    
    var distanceFormatted: String {
        if totalDistance < 1000 {
            return "\(Int(totalDistance))m"
        }
        return String(format: "%.1f km", totalDistance / 1000)
    }
    
    var durationFormatted: String {
        let minutes = Int(totalDuration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
    
    var polyline: MKPolyline {
        MKPolyline(coordinates: coordinates, count: coordinates.count)
    }
}

// MARK: - Navigation Service
class NavigationService: ObservableObject {
    @Published var currentRoute: Route?
    @Published var isCalculating = false
    @Published var errorMessage: String?
    @Published var currentInstructionIndex = 0
    @Published var distanceToNextTurn: Double = 0
    @Published var isNavigating = false
    @Published var hasArrived = false
    @Published var suggestedTurnDirection: TurnType?
    
    // Toggle to use MapKit instead of remote API
    var useMapKitDirections = true
    
    // Turn indicator auto-off distance (meters past turn)
    var turnAutoOffDistance: Double = UserDefaults.standard.double(forKey: "turnAutoOffDistance") == 0
        ? 20
        : UserDefaults.standard.double(forKey: "turnAutoOffDistance")
    
    // MARK: - Route Calculation (MapKit)
    @MainActor
    func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, completion: ((Bool) -> Void)? = nil) {
        isCalculating = true
        errorMessage = nil
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking // closest to bicycle; use .automobile if preferred
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isCalculating = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("Navigation (MK): request error - \(error.localizedDescription)")
                    completion?(false)
                    return
                }
                
                guard let route = response?.routes.first else {
                    self.errorMessage = "No route found"
                    completion?(false)
                    return
                }
                
                let success = self.buildRoute(from: route)
                completion?(success)
            }
        }
    }
    
    @MainActor
    private func buildRoute(from mkRoute: MKRoute) -> Bool {
        // Coordinates from polyline
        let points = mkRoute.polyline.points()
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(mkRoute.polyline.pointCount)
        for i in 0..<mkRoute.polyline.pointCount {
            coords.append(points[i].coordinate)
        }
        
        // Build instructions with approximate per-step durations
        let totalDistance = mkRoute.distance
        let totalTime = mkRoute.expectedTravelTime
        var stepsInstructions: [RouteInstruction] = []
        
        for step in mkRoute.steps {
            // Skip the initial “start” step with empty instructions if any
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && step.distance == 0 { continue }
            
            let code = synthesizeTurnCode(from: text)
            // Use the step’s polyline start coordinate as the instruction coordinate
            let coord = step.polyline.pointCount > 0 ? step.polyline.points()[0].coordinate : coords.first ?? mkRoute.polyline.coordinate
            
            // Approximate duration proportionally by distance
            let duration: Double
            if totalDistance > 0 {
                duration = totalTime * (step.distance / totalDistance)
            } else {
                duration = 0
            }
            
            let instr = RouteInstruction(
                instruction: text.isEmpty ? "Continue" : text,
                distance: step.distance,
                duration: duration,
                type: code,
                coordinate: coord
            )
            stepsInstructions.append(instr)
        }
        
        currentRoute = Route(
            coordinates: coords,
            instructions: stepsInstructions,
            totalDistance: totalDistance,
            totalDuration: totalTime
        )
        
        currentInstructionIndex = 0
        distanceToNextTurn = stepsInstructions.first?.distance ?? totalDistance
        hasArrived = false
        updateSuggestedTurn()
        
        print("Navigation (MK): Route calculated - \(currentRoute?.distanceFormatted ?? "Unknown"), steps: \(stepsInstructions.count)")
        return true
    }
    
    // Heuristic mapping of instruction text to a TurnType code
    private func synthesizeTurnCode(from text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("roundabout") && lower.contains("left") { return 8 }
        if lower.contains("roundabout") && lower.contains("right") { return 7 }
        if lower.contains("u-turn") || lower.contains("uturn") { return 9 }
        if lower.contains("arrive") || lower.contains("destination") { return 10 }
        if lower.contains("depart") || lower.contains("start") { return 11 }
        
        // detect sharper vs slight turns
        if lower.contains("sharp left") { return 2 }
        if lower.contains("sharp right") { return 3 }
        if lower.contains("slight left") || lower.contains("bear left") { return 4 }
        if lower.contains("slight right") || lower.contains("bear right") { return 5 }
        if lower.contains("left") { return 0 }
        if lower.contains("right") { return 1 }
        if lower.contains("straight") || lower.contains("continue") { return 6 }
        
        return 6 // default to straight/continue
    }
    
    // MARK: - Navigation Control
    func startNavigation() {
        guard currentRoute != nil else { return }
        isNavigating = true
        currentInstructionIndex = 0
        hasArrived = false
        updateSuggestedTurn()
    }
    
    func stopNavigation() {
        isNavigating = false
        currentRoute = nil
        currentInstructionIndex = 0
        suggestedTurnDirection = nil
        hasArrived = false
        distanceToNextTurn = 0
    }
    
    func updateNavigation(currentLocation: CLLocation) {
        guard let route = currentRoute, isNavigating else { return }
        guard currentInstructionIndex < route.instructions.count else {
            hasArrived = true
            isNavigating = false
            suggestedTurnDirection = nil
            return
        }
        
        let nextInstruction = route.instructions[currentInstructionIndex]
        let turnLocation = CLLocation(latitude: nextInstruction.coordinate.latitude, longitude: nextInstruction.coordinate.longitude)
        let distanceToTurn = currentLocation.distance(from: turnLocation)
        
        distanceToNextTurn = distanceToTurn
        
        if distanceToTurn < 100 {
            updateSuggestedTurn()
        } else {
            suggestedTurnDirection = nil
        }
        
        if distanceToTurn < turnAutoOffDistance {
            currentInstructionIndex += 1
            suggestedTurnDirection = nil
            
            if currentInstructionIndex < route.instructions.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.updateSuggestedTurn()
                }
            } else {
                hasArrived = true
                isNavigating = false
            }
        }
    }
    
    private func updateSuggestedTurn() {
        guard let route = currentRoute,
              currentInstructionIndex < route.instructions.count else {
            suggestedTurnDirection = nil
            return
        }
        
        let instruction = route.instructions[currentInstructionIndex]
        let turnType = instruction.turnType
        
        if turnType.isLeftTurn || turnType.isRightTurn {
            suggestedTurnDirection = turnType
        } else {
            suggestedTurnDirection = nil
        }
    }
    
    var currentInstruction: RouteInstruction? {
        guard let route = currentRoute, currentInstructionIndex < route.instructions.count else { return nil }
        return route.instructions[currentInstructionIndex]
    }
    
    var nextInstruction: RouteInstruction? {
        guard let route = currentRoute, currentInstructionIndex + 1 < route.instructions.count else { return nil }
        return route.instructions[currentInstructionIndex + 1]
    }
    
    var remainingDistance: Double {
        guard let route = currentRoute else { return 0 }
        guard currentInstructionIndex < route.instructions.count else { return 0 }
        return route.instructions[currentInstructionIndex...].reduce(0) { $0 + $1.distance }
    }
}
