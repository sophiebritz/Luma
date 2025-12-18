//
//  NavigationView.swift
//  SmartHelmetApp
//
//  Navigation with auto-indication for turn signals
//

import SwiftUI
import MapKit

// Helper extension to get coordinate from MKMapItem (iOS 18+ compatible)
extension MKMapItem {
    var coordinate: CLLocationCoordinate2D {
        // Use placemark.coordinate for compatibility
        // This suppresses the deprecation warning
        return self.placemark.coordinate
    }
    
    var address: String? {
        // Get address from placemark
        return self.placemark.title
    }
}

struct NavigationMapView: View {
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var selectedDestination: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showRoutePreview = false
    
    var body: some View {
        ZStack {
            // Map
            mapView
            
            // Overlays
            VStack {
                // Top bar
                if !navigationService.isNavigating {
                    searchBar
                }
                
                Spacer()
                
                // Bottom panels
                if navigationService.isNavigating {
                    navigationPanel
                } else if showRoutePreview, let _ = selectedDestination {
                    routePreviewPanel
                }
            }
            
            // Auto-indicate status
            if navigationService.autoIndicateActive {
                autoIndicateOverlay
            }
        }
        .onAppear {
            navigationService.bluetoothManager = bluetoothManager
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(
                searchText: $searchText,
                selectedDestination: $selectedDestination,
                showRoutePreview: $showRoutePreview,
                showSearch: $showSearch
            )
            .environmentObject(navigationService)
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // User location
            UserAnnotation()
            
            // Route polyline
            if let route = navigationService.currentRoute {
                MapPolyline(route.polyline)
                    .stroke(.orange, lineWidth: 6)
            }
            
            // Destination marker
            if let destination = selectedDestination {
                Marker(destination.name ?? "Destination", coordinate: destination.coordinate)
                    .tint(.orange)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
        // Zoom to route when calculated
        .onChange(of: navigationService.currentRoute) { _, newRoute in
            if let route = newRoute {
                zoomToRoute(route)
            }
        }
        // Follow user when navigating
        .onChange(of: navigationService.isNavigating) { _, isNavigating in
            if isNavigating {
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
            }
        }
    }
    
    private func zoomToRoute(_ route: MKRoute) {
        let rect = route.polyline.boundingMapRect
        // Add padding by expanding the rect
        let paddedRect = rect.insetBy(dx: -rect.size.width * 0.2, dy: -rect.size.height * 0.3)
        let region = MKCoordinateRegion(paddedRect)
        cameraPosition = .region(region)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        Button(action: { showSearch = true }) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                Text("Search destination...")
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding()
        }
    }
    
    // MARK: - Navigation Panel
    
    private var navigationPanel: some View {
        VStack(spacing: 0) {
            // Current instruction
            HStack(spacing: 16) {
                // Turn direction icon
                ZStack {
                    Circle()
                        .fill(navigationService.nextTurnDirection != nil ? Color.orange : Color.gray)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: navigationService.nextTurnDirection?.icon ?? "arrow.up")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDistance(navigationService.distanceToNextTurn))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text(navigationService.currentInstruction)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .padding()
            .background(.ultraThickMaterial)
            
            // Auto-indicate toggle & stats
            HStack {
                // Auto-indicate toggle
                Toggle(isOn: $navigationService.autoIndicateEnabled) {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundColor(.orange)
                        Text("Auto Turn Signals")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                
                Spacer()
                
                // ETA
                VStack(alignment: .trailing) {
                    Text(formatTime(navigationService.estimatedTimeRemaining))
                        .font(.system(size: 16, weight: .bold))
                    Text(formatDistance(navigationService.totalDistanceRemaining))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // Stop navigation button
            Button(action: { navigationService.stopNavigation() }) {
                Text("End Navigation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
            }
            
            // Debug: Test signal buttons
            HStack(spacing: 12) {
                Button(action: { navigationService.testAutoIndicate(direction: .left) }) {
                    Label("Test Left", systemImage: "arrow.turn.up.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Button(action: { navigationService.testAutoIndicate(direction: .right) }) {
                    Label("Test Right", systemImage: "arrow.turn.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                // Connection status
                Circle()
                    .fill(bluetoothManager.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(bluetoothManager.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
    
    // MARK: - Route Preview Panel
    
    private var routePreviewPanel: some View {
        VStack(spacing: 16) {
            if let destination = selectedDestination {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.name ?? "Destination")
                            .font(.system(size: 18, weight: .bold))
                        
                        if let route = navigationService.currentRoute {
                            HStack(spacing: 4) {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 12))
                                Text("\(formatDistance(route.distance)) â€¢ \(formatTime(route.expectedTravelTime))")
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            
                            Text("Driving route (cycling not supported by Apple Maps)")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showRoutePreview = false
                        selectedDestination = nil
                        navigationService.currentRoute = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                
                // Helmet connection status
                HStack {
                    Circle()
                        .fill(bluetoothManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(bluetoothManager.isConnected ? "Helmet connected - Auto signals ready" : "Connect helmet for auto signals")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                // Start button
                Button(action: {
                    if let route = navigationService.currentRoute {
                        navigationService.startNavigation(with: route)
                        showRoutePreview = false
                    }
                }) {
                    HStack {
                        Image(systemName: "bicycle")
                        Text("Start Ride")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(16)
                }
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
    
    // MARK: - Auto-Indicate Overlay
    
    private var autoIndicateOverlay: some View {
        VStack {
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: navigationService.currentAutoTurn?.icon ?? "arrow.left.arrow.right")
                        .font(.title2)
                    
                    Text("SIGNAL \(navigationService.currentAutoTurn?.title ?? "")")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange)
                .cornerRadius(20)
                .padding()
                
                Spacer()
            }
            
            Spacer()
        }
        .padding(.top, 60)
    }
    
    // MARK: - Helpers
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return "\(Int(meters)) m"
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Search Sheet

struct SearchSheet: View {
    @Binding var searchText: String
    @Binding var selectedDestination: MKMapItem?
    @Binding var showRoutePreview: Bool
    @Binding var showSearch: Bool
    
    @EnvironmentObject var navigationService: NavigationService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search destination", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            navigationService.searchPlaces(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()
                
                // Results
                if navigationService.isSearching {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if navigationService.searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No results found")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    Spacer()
                } else {
                    List(navigationService.searchResults, id: \.self) { item in
                        Button(action: {
                            selectDestination(item)
                        }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    if let address = item.address {
                                        Text(address)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showSearch = false
                    }
                }
            }
        }
    }
    
    private func selectDestination(_ item: MKMapItem) {
        selectedDestination = item
        showSearch = false
        showRoutePreview = true
        
        // Calculate route
        navigationService.calculateRoute(to: item)
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    NavigationMapView()
        .environmentObject(NavigationService())
        .environmentObject(BluetoothManager())
}
