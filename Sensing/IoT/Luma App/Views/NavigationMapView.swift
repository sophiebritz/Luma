//
//  NavigationMapView.swift
//  LumaHelmet
//
//  Map view with navigation and turn signaling - iOS 17+
//

import SwiftUI
import MapKit

struct NavigationMapView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var rideService: RideService
    @EnvironmentObject var navigationService: NavigationService
    
    @StateObject private var placesService = PlacesService()
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var selectedDestination: CLLocationCoordinate2D?
    @State private var destinationName: String?
    @State private var leftIndicatorActive = false
    @State private var rightIndicatorActive = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Map with route overlay
                mapView
                
                // Overlays
                VStack(spacing: 0) {
                    // Search bar (when active)
                    if showSearch {
                        searchOverlay
                    }
                    
                    // Navigation instruction card
                    if navigationService.isNavigating, let instruction = navigationService.currentInstruction {
                        NavigationInstructionCard(
                            instruction: instruction,
                            distance: navigationService.distanceToNextTurn,
                            nextInstruction: navigationService.nextInstruction
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 12) {
                        // Speed display
                        SpeedDisplay(speed: locationService.currentSpeed)
                        
                        // Turn indicators (when connected)
                        if bleManager.isConnected {
                            TurnIndicatorBar(
                                leftActive: $leftIndicatorActive,
                                rightActive: $rightIndicatorActive,
                                suggestedDirection: navigationService.suggestedTurnDirection
                            )
                            .environmentObject(bleManager)
                        }
                        
                        // Navigation controls
                        NavigationControlBar(
                            showSearch: $showSearch,
                            selectedDestination: $selectedDestination,
                            destinationName: $destinationName
                        )
                        .environmentObject(navigationService)
                        .environmentObject(locationService)
                        .environmentObject(rideService)
                    }
                    .padding()
                }
            }
            .navigationTitle("Navigate")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                handleAppear()
            }
            .onDisappear {
                handleDisappear()
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                if let location = newLocation, navigationService.isNavigating {
                    navigationService.updateNavigation(currentLocation: location)
                }
            }
            // Auto-activate turn indicators based on navigation suggestion
            .onChange(of: navigationService.suggestedTurnDirection) { _, direction in
                updateTurnIndicators(for: direction)
            }
            // Auto-clear manual indicators when we pass the turn threshold
            .onChange(of: navigationService.distanceToNextTurn) { _, newDistance in
                autoClearIndicatorsIfNeeded(distance: newDistance)
            }
        }
    }
    
    // MARK: - Map View
    @ViewBuilder
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // User location
            UserAnnotation()
            
            // Destination marker
            if let dest = selectedDestination {
                Marker(destinationName ?? "Destination", coordinate: dest)
                    .tint(.red)
            }
            
            // Route polyline
            if let route = navigationService.currentRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.blue, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - Search Overlay
    private var searchOverlay: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search destination", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        placesService.searchPlaces(query: newValue, near: locationService.currentLocation)
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        placesService.clearSuggestions()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button("Cancel") {
                    showSearch = false
                    searchText = ""
                    placesService.clearSuggestions()
                }
                .foregroundStyle(.blue)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            // Suggestions
            if !placesService.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(placesService.suggestions) { suggestion in
                        Button {
                            selectDestination(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.subheadline)
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal)
                        }
                        .foregroundStyle(.primary)
                        
                        if suggestion.id != placesService.suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    private func handleAppear() {
        // Always start tracking when map appears if riding
        if rideService.isRiding {
            locationService.upgradeToNavigationMode()
        } else {
            locationService.startNavigationMode()
        }
        
        // Center on user location
        if let location = locationService.currentLocation {
            cameraPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
    
    private func handleDisappear() {
        // Only downgrade if not actively navigating
        if !navigationService.isNavigating {
            if rideService.isRiding {
                locationService.downgradeToLoggingMode()
            } else {
                locationService.stopTracking()
            }
        }
    }
    
    private func selectDestination(_ suggestion: PlaceSuggestion) {
        selectedDestination = suggestion.coordinate
        destinationName = suggestion.title
        showSearch = false
        searchText = suggestion.title
        placesService.clearSuggestions()
        
        // Center map to show route
        cameraPosition = .region(MKCoordinateRegion(
            center: suggestion.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }
    
    private func updateTurnIndicators(for direction: TurnType?) {
        guard bleManager.isConnected else { return }
        
        if let direction = direction {
            if direction.isLeftTurn && !leftIndicatorActive {
                leftIndicatorActive = true
                rightIndicatorActive = false
                bleManager.turnLeftOn()
            } else if direction.isRightTurn && !rightIndicatorActive {
                rightIndicatorActive = true
                leftIndicatorActive = false
                bleManager.turnRightOn()
            }
        } else {
            // Clear indicators when no turn suggested
            if leftIndicatorActive || rightIndicatorActive {
                leftIndicatorActive = false
                rightIndicatorActive = false
                bleManager.turnOff()
            }
        }
    }
    
    // Auto-clear manual indicators when we pass the turn threshold
    private func autoClearIndicatorsIfNeeded(distance: Double) {
        guard bleManager.isConnected else { return }
        // Only consider auto-off while navigating with a route
        guard navigationService.isNavigating, navigationService.currentRoute != nil else { return }
        
        if distance <= navigationService.turnAutoOffDistance {
            if leftIndicatorActive || rightIndicatorActive {
                leftIndicatorActive = false
                rightIndicatorActive = false
                bleManager.turnOff()
            }
        }
    }
}

// MARK: - Navigation Instruction Card
struct NavigationInstructionCard: View {
    let instruction: RouteInstruction
    let distance: Double
    let nextInstruction: RouteInstruction?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: instruction.turnType.iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .frame(width: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(instruction.instruction)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(formatDistance(distance))
                        .font(.title2.bold())
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                }
                
                Spacer()
            }
            
            // Next instruction preview
            if let next = nextInstruction {
                Divider()
                HStack {
                    Text("Then")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: next.turnType.iconName)
                        .foregroundStyle(.secondary)
                    
                    Text(next.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters)) m"
        } else if meters < 1000 {
            return "\(Int(meters / 10) * 10) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - Speed Display
struct SpeedDisplay: View {
    let speed: Double // m/s
    
    private var speedKmh: Int {
        Int(speed * 3.6)
    }
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 2) {
                Text("\(speedKmh)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Turn Indicator Bar
struct TurnIndicatorBar: View {
    @EnvironmentObject var bleManager: BLEManager
    @Binding var leftActive: Bool
    @Binding var rightActive: Bool
    let suggestedDirection: TurnType?
    
    var body: some View {
        HStack(spacing: 40) {
            // Left turn button
            TurnButton(
                direction: .left,
                isActive: leftActive,
                isSuggested: suggestedDirection?.isLeftTurn == true
            ) {
                leftActive.toggle()
                rightActive = false
                if leftActive {
                    bleManager.turnLeftOn()
                } else {
                    bleManager.turnOff()
                }
            }
            
            // Right turn button
            TurnButton(
                direction: .right,
                isActive: rightActive,
                isSuggested: suggestedDirection?.isRightTurn == true
            ) {
                rightActive.toggle()
                leftActive = false
                if rightActive {
                    bleManager.turnRightOn()
                } else {
                    bleManager.turnOff()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct TurnButton: View {
    enum Direction { case left, right }
    
    let direction: Direction
    let isActive: Bool
    let isSuggested: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right")
                .font(.title)
                .foregroundStyle(isActive ? .white : (isSuggested ? .orange : .gray))
                .frame(width: 64, height: 64)
                .background(
                    isActive ? Color.orange : (isSuggested ? Color.orange.opacity(0.2) : Color(.systemGray5))
                )
                .clipShape(Circle())
                .overlay {
                    if isSuggested && !isActive {
                        Circle()
                            .strokeBorder(Color.orange, lineWidth: 2)
                    }
                }
        }
    }
}

// MARK: - Navigation Control Bar
struct NavigationControlBar: View {
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var rideService: RideService
    
    @Binding var showSearch: Bool
    @Binding var selectedDestination: CLLocationCoordinate2D?
    @Binding var destinationName: String?
    
    var body: some View {
        HStack(spacing: 12) {
            if navigationService.isNavigating {
                // Active navigation controls
                Button(role: .destructive) {
                    navigationService.stopNavigation()
                    selectedDestination = nil
                    destinationName = nil
                } label: {
                    Label("Stop", systemImage: "xmark")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                // Remaining distance/time
                if let route = navigationService.currentRoute {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(route.distanceFormatted)
                            .font(.headline)
                        Text(route.durationFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Pre-navigation controls
                Button {
                    showSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                
                if selectedDestination != nil {
                    Button {
                        startNavigation()
                    } label: {
                        Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func startNavigation() {
        guard let start = locationService.currentLocation?.coordinate,
              let end = selectedDestination else { return }
        
        // Start ride tracking if not already
        if !rideService.isRiding {
            rideService.startRide()
        }
        
        // Ensure navigation-mode tracking
        locationService.upgradeToNavigationMode()
        
        // Calculate route and start navigation when ready
        navigationService.calculateRoute(from: start, to: end) { success in
            if success {
                navigationService.startNavigation()
            } else {
                print("Navigation: failed to calculate route")
            }
        }
    }
}
