//
//  ContentView.swift
//  LumaHelmet
//
//  Main tab navigation with proper ride tracking - iOS 17+
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var rideService: RideService
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            NavigationMapView()
                .tabItem {
                    Label("Navigate", systemImage: "map.fill")
                }
                .tag(1)
            
            WeatherView()
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun.fill")
                }
                .tag(2)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
        .tint(.blue)
        .onAppear {
            locationService.requestAuthorization()
        }
        // Handle tab changes - upgrade location tracking when navigating
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 1 && rideService.isRiding {
                // Switching to navigation tab while riding - upgrade to nav mode
                locationService.upgradeToNavigationMode()
            } else if oldValue == 1 && rideService.isRiding && newValue != 1 {
                // Leaving navigation tab while riding - can downgrade if not actively navigating
                // Keep nav mode if actively navigating
            }
        }
        // Crash alert
        .alert("Crash Detected!", isPresented: $bleManager.showCrashAlert) {
            Button("I'm OK - Dismiss", role: .cancel) {
                bleManager.dismissCrash()
            }
            Button("Call Emergency Contact", role: .destructive) {
                callEmergencyContact()
            }
        } message: {
            Text("A crash has been detected. If you're okay, dismiss this alert. Otherwise, your emergency contact will be notified.")
        }
    }
    
    private func callEmergencyContact() {
        if let phone = UserDefaults.standard.string(forKey: "emergencyContact"),
           let url = URL(string: "tel://\(phone)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        bleManager.dismissCrash()
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var rideService: RideService
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Connection card
                    ConnectionCard()
                    
                    // Ride card
                    if rideService.isRiding {
                        CurrentRideCard()
                    } else {
                        StartRideCard()
                    }
                    
                    // Quick stats
                    QuickStatsCard()
                    
                    // Recent events
                    if !bleManager.detectedEvents.isEmpty {
                        RecentEventsCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Luma Helmet")
            .refreshable {
                if let location = locationService.currentLocation {
                    weatherService.fetchWeather(for: location)
                }
            }
        }
    }
}

// MARK: - Connection Card
struct ConnectionCard: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showDeviceSheet = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: bleManager.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(bleManager.isConnected ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Helmet Status")
                        .font(.headline)
                    Text(bleManager.connectionStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(bleManager.isConnected ? "Disconnect" : "Connect") {
                    if bleManager.isConnected {
                        bleManager.disconnect()
                    } else {
                        showDeviceSheet = true
                        bleManager.startScanning()
                    }
                }
                .buttonStyle(.bordered)
                .tint(bleManager.isConnected ? .red : .blue)
            }
            
            if bleManager.isConnected {
                Divider()
                
                HStack(spacing: 20) {
                    Button {
                        bleManager.partyModeOn()
                    } label: {
                        VStack {
                            Image(systemName: "sparkles")
                            Text("Party").font(.caption)
                        }
                    }
                    .foregroundStyle(.purple)
                    
                    Button {
                        bleManager.partyModeOff()
                    } label: {
                        VStack {
                            Image(systemName: "moon.fill")
                            Text("Normal").font(.caption)
                        }
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showDeviceSheet) {
            DeviceListSheet()
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Device List Sheet
struct DeviceListSheet: View {
    @EnvironmentObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if bleManager.isScanning {
                    HStack {
                        ProgressView()
                        Text("Scanning...")
                            .foregroundStyle(.secondary)
                    }
                }
                
                ForEach(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button {
                        bleManager.connect(to: peripheral)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.blue)
                            Text(peripheral.name ?? "Unknown Device")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                if bleManager.discoveredPeripherals.isEmpty && !bleManager.isScanning {
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect Helmet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bleManager.stopScanning()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Start Ride Card
struct StartRideCard: View {
    @EnvironmentObject var rideService: RideService
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var locationService: LocationService
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            Text("Ready to Ride?")
                .font(.title2.bold())
            
            Text("Start tracking for safety analytics")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                rideService.startRide(weatherState: weatherService.weatherState)
            } label: {
                Label("Start Ride", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Current Ride Card
struct CurrentRideCard: View {
    @EnvironmentObject var rideService: RideService
    @EnvironmentObject var locationService: LocationService
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Ride")
                        .font(.headline)
                    Text(rideService.currentSession?.durationFormatted ?? "0 min")
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                
                Spacer()
                
                // Safety score circle
                SafetyScoreCircle(score: rideService.currentSafetyScore)
            }
            
            // Live stats row
            HStack(spacing: 12) {
                LiveStatItem(title: "Distance", value: formatDistance(rideService.liveDistance), icon: "map")
                LiveStatItem(title: "Speed", value: formatSpeed(rideService.liveSpeed), icon: "speedometer")
                LiveStatItem(title: "Max", value: formatSpeed(rideService.liveMaxSpeed), icon: "arrow.up")
                LiveStatItem(title: "Avg", value: formatSpeed(rideService.liveAvgSpeed), icon: "equal")
            }
            
            // Event counts (show brakes and crashes only)
            HStack(spacing: 16) {
                EventCountBadge(icon: "hand.raised.fill", count: rideService.currentSession?.brakeCount ?? 0, color: .orange)
                EventCountBadge(icon: "exclamationmark.triangle.fill", count: rideService.currentSession?.crashCount ?? 0, color: .red)
            }
            
            Button(role: .destructive) {
                _ = rideService.endRide()
                locationService.stopTracking()
            } label: {
                Label("End Ride", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }
    
    private func formatSpeed(_ mps: Double) -> String {
        String(format: "%.0f", mps * 3.6)
    }
}

struct SafetyScoreCircle: View {
    let score: Int
    
    private var color: Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text("\(score)")
                .font(.title2.bold())
                .monospacedDigit()
        }
        .frame(width: 60, height: 60)
    }
}

struct LiveStatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.caption)
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EventCountBadge: View {
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Quick Stats Card
struct QuickStatsCard: View {
    @EnvironmentObject var rideService: RideService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Stats")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatCard(title: "Rides", value: "\(rideService.totalRides)", icon: "bicycle", color: .blue)
                StatCard(title: "Distance", value: formatDistance(rideService.totalDistance), icon: "map", color: .green)
                StatCard(title: "Safety", value: "\(rideService.averageSafetyScore)", icon: "shield.checkered", color: .orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recent Events Card
struct RecentEventsCard: View {
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)
            
            ForEach(bleManager.detectedEvents.filter { $0.eventClass != .bump }.prefix(5)) { event in
                HStack {
                    Image(systemName: event.eventClass.iconName)
                        .foregroundStyle(Color(event.eventClass.colorName))
                    
                    Text(event.eventClass.name)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let appState = AppState()
    return ContentView()
        .environmentObject(appState)
        .environmentObject(appState.bleManager)
        .environmentObject(appState.locationService)
        .environmentObject(appState.weatherService)
        .environmentObject(appState.rideService)
        .environmentObject(appState.navigationService)
}
