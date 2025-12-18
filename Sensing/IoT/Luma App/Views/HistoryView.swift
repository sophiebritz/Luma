//
//  HistoryView.swift
//  LumaHelmet
//
//  Ride history with map display for each ride - iOS 17+
//

import SwiftUI
import MapKit

struct HistoryView: View {
    @EnvironmentObject var rideService: RideService
    
    var body: some View {
        NavigationStack {
            List {
                // Overall stats section
                Section("Overall Statistics") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        HistoryStatCard(title: "Total Rides", value: "\(rideService.totalRides)", icon: "bicycle", color: .blue)
                        HistoryStatCard(title: "Distance", value: formatDistance(rideService.totalDistance), icon: "map", color: .green)
                        HistoryStatCard(title: "Avg Safety", value: "\(rideService.averageSafetyScore)", icon: "shield.checkered", color: .orange)
                        HistoryStatCard(title: "Best Score", value: "\(rideService.bestSafetyScore)", icon: "star.fill", color: .yellow)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                
                // Ride history section
                Section("Recent Rides") {
                    if rideService.rideHistory.isEmpty {
                        ContentUnavailableView {
                            Label("No Rides Yet", systemImage: "bicycle")
                        } description: {
                            Text("Start your first ride from the Home tab")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(rideService.rideHistory) { ride in
                            NavigationLink(destination: RideDetailView(ride: ride)) {
                                RideHistoryRow(ride: ride)
                            }
                        }
                        .onDelete(perform: deleteRides)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .toolbar {
                if !rideService.rideHistory.isEmpty {
                    EditButton()
                }
            }
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
    
    private func deleteRides(at offsets: IndexSet) {
        for index in offsets {
            rideService.deleteRide(rideService.rideHistory[index])
        }
    }
}

// MARK: - Stat Card
struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Ride History Row
struct RideHistoryRow: View {
    let ride: RideSession
    
    private var safetyColor: Color {
        if ride.safetyScore >= 80 { return .green }
        if ride.safetyScore >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Safety score badge
            ZStack {
                Circle()
                    .fill(safetyColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Text("\(ride.safetyScore)")
                    .font(.headline.bold())
                    .foregroundStyle(safetyColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.startTime, format: .dateTime.weekday().month().day())
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label(ride.distanceFormatted, systemImage: "map")
                    Label(ride.durationFormatted, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                // Speed info
                HStack(spacing: 12) {
                    Label(String(format: "%.0f km/h avg", ride.avgSpeedKmh), systemImage: "speedometer")
                    Label(String(format: "%.0f km/h max", ride.maxSpeedKmh), systemImage: "arrow.up")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Event indicators (brakes/crashes only)
            VStack(alignment: .trailing, spacing: 4) {
                if ride.crashCount > 0 {
                    Label("\(ride.crashCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if ride.brakeCount > 0 {
                    Label("\(ride.brakeCount)", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ride Detail View with Map
struct RideDetailView: View {
    let ride: RideSession
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Route map
                if !ride.routeCoordinates.isEmpty {
                    RideMapView(coordinates: ride.routeCoordinates)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // No route data available
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 200)
                        .overlay {
                            VStack {
                                Image(systemName: "map")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No route data")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                
                // Summary stats
                SummarySection(ride: ride)
                
                // Speed stats
                SpeedSection(ride: ride)
                
                // Safety section
                SafetySection(ride: ride)
                
                // Events list
                if !ride.events.isEmpty {
                    EventsSection(events: ride.events)
                }
            }
            .padding()
        }
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ride Map View
struct RideMapView: View {
    let coordinates: [CodableCoordinate]
    
    private var polylineCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.coordinate }
    }
    
    private var region: MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion()
        }
        
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3 + 0.005,
            longitudeDelta: (maxLon - minLon) * 1.3 + 0.005
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var body: some View {
        Map(initialPosition: .region(region)) {
            // Route polyline
            if polylineCoordinates.count > 1 {
                MapPolyline(coordinates: polylineCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            
            // Start marker
            if let first = coordinates.first {
                Marker("Start", coordinate: first.coordinate)
                    .tint(.green)
            }
            
            // End marker
            if let last = coordinates.last, coordinates.count > 1 {
                Marker("End", coordinate: last.coordinate)
                    .tint(.red)
            }
        }
        .mapStyle(.standard)
    }
}

// MARK: - Detail Sections
struct SummarySection: View {
    let ride: RideSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DetailItem(title: "Distance", value: ride.distanceFormatted, icon: "map")
                DetailItem(title: "Duration", value: ride.durationFormatted, icon: "clock")
                DetailItem(title: "Date", value: ride.startTime.formatted(date: .abbreviated, time: .omitted), icon: "calendar")
                DetailItem(title: "Weather", value: ride.weatherState, icon: "cloud.sun")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SpeedSection: View {
    let ride: RideSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", ride.avgSpeedKmh))
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("km/h avg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", ride.maxSpeedKmh))
                        .font(.title.bold())
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                    Text("km/h max")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SafetySection: View {
    let ride: RideSession
    
    private var safetyColor: Color {
        if ride.safetyScore >= 80 { return .green }
        if ride.safetyScore >= 50 { return .orange }
        return .red
    }
    
    private var safetyBand: String {
        if ride.safetyScore >= 80 { return "Safe" }
        if ride.safetyScore >= 50 { return "Moderate" }
        return "High Risk"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safety")
                .font(.headline)
            
            HStack {
                // Score display
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(safetyColor.opacity(0.3), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(ride.safetyScore) / 100)
                            .stroke(safetyColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(ride.safetyScore)")
                            .font(.title.bold())
                            .monospacedDigit()
                    }
                    
                    Text(safetyBand)
                        .font(.caption)
                        .foregroundStyle(safetyColor)
                }
                
                Spacer()
                
                // Event counts (brakes/crashes only)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                        Text("Brakes: \(ride.brakeCount)")
                    }
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Crashes: \(ride.crashCount)")
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EventsSection: View {
    let events: [CodableEvent]
    
    var body: some View {
        let filtered = events.filter { $0.eventClass != .bump }
        VStack(alignment: .leading, spacing: 12) {
            Text("Events (\(filtered.count))")
                .font(.headline)
            
            ForEach(filtered.prefix(10)) { event in
                HStack {
                    Image(systemName: event.eventClass.iconName)
                        .foregroundStyle(Color(event.eventClass.colorName))
                    
                    Text(event.eventClass.name)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "%.0f%%", event.confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if filtered.count > 10 {
                Text("+ \(filtered.count - 10) more events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DetailItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
            }
            
            Spacer()
        }
    }
}
