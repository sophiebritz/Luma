//
//  RideHistoryView.swift
//  SmartHelmetApp
//
//  Displays ride history with InfluxDB upload functionality
//

import SwiftUI

struct RideHistoryView: View {
    @StateObject private var rideTracker = RideTracker.shared
    @StateObject private var influxDB = InfluxDBService.shared
    @State private var selectedTimeFrame: TimeFrame = .week
    @State private var showingSettings = false
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    var filteredRides: [RideSession] {
        let calendar = Calendar.current
        let now = Date()
        
        return rideTracker.rideHistory.filter { ride in
            switch selectedTimeFrame {
            case .week:
                return calendar.isDate(ride.startTime, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(ride.startTime, equalTo: now, toGranularity: .month)
            case .year:
                return calendar.isDate(ride.startTime, equalTo: now, toGranularity: .year)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Cloud status banner
                        cloudStatusBanner
                        
                        // Time frame picker
                        timeFramePicker
                        
                        // Stats summary
                        statsSummary
                        
                        // Ride list
                        if rideTracker.rideHistory.isEmpty {
                            emptyState
                        } else {
                            rideList
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            }
            .navigationTitle("Ride History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(hex: "1a1a2e"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingSettings = true }) {
                            Label("InfluxDB Settings", systemImage: "gear")
                        }
                        
                        Button(action: uploadAllRides) {
                            Label("Upload All to Cloud", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(!influxDB.isConfigured)
                        
                        Button(role: .destructive, action: {
                            rideTracker.clearHistory()
                        }) {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                InfluxDBSettingsView()
            }
        }
    }
    
    // MARK: - Cloud Status Banner
    
    private var cloudStatusBanner: some View {
        HStack {
            Image(systemName: influxDB.isConfigured ? "checkmark.icloud" : "xmark.icloud")
                .foregroundColor(influxDB.isConfigured ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(influxDB.isConfigured ? "InfluxDB Connected" : "InfluxDB Not Configured")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(influxDB.lastUploadStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if !influxDB.isConfigured {
                Button("Setup") {
                    showingSettings = true
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Time Frame Picker
    
    private var timeFramePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeFrame.allCases, id: \.self) { frame in
                Button(action: { selectedTimeFrame = frame }) {
                    Text(frame.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(selectedTimeFrame == frame ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTimeFrame == frame ? Color.orange : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Stats Summary
    
    private var statsSummary: some View {
        let totalDistance = filteredRides.reduce(0) { $0 + $1.distance }
        let totalDuration = filteredRides.reduce(0) { $0 + $1.duration }
        let avgSpeed = filteredRides.isEmpty ? 0 : filteredRides.reduce(0) { $0 + $1.averageSpeed } / Double(filteredRides.count)
        let totalTurns = filteredRides.reduce(0) { $0 + $1.turnLeftCount + $1.turnRightCount }
        
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(
                    title: "Total Distance",
                    value: formatDistance(totalDistance),
                    icon: "road.lanes",
                    color: .orange
                )
                
                StatCard(
                    title: "Total Time",
                    value: formatDuration(totalDuration),
                    icon: "clock.fill",
                    color: .blue
                )
            }
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Avg Speed",
                    value: String(format: "%.1f km/h", avgSpeed),
                    icon: "speedometer",
                    color: .green
                )
                
                StatCard(
                    title: "Turn Signals",
                    value: "\(totalTurns)",
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Ride List
    
    private var rideList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Rides")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(filteredRides) { ride in
                RideCard(ride: ride, influxDB: influxDB) {
                    Task {
                        await rideTracker.uploadRide(ride)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No rides yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Start navigating to record your first ride!")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func uploadAllRides() {
        Task {
            let count = await rideTracker.uploadAllRides()
            print("Uploaded \(count) rides")
        }
    }
    
    // MARK: - Helpers
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins) min"
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Ride Card

struct RideCard: View {
    let ride: RideSession
    let influxDB: InfluxDBService
    let onUpload: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ride.startLocationName ?? "Ride")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(ride.startTime))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Upload status
                if ride.uploadedToCloud {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundColor(.green)
                } else if influxDB.isConfigured {
                    Button(action: onUpload) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Stats row
            HStack(spacing: 20) {
                RideStatItem(icon: "road.lanes", value: formatDistance(ride.distance))
                RideStatItem(icon: "clock", value: formatDuration(ride.duration))
                RideStatItem(icon: "speedometer", value: String(format: "%.1f", ride.averageSpeed) + " km/h")
            }
            
            // Events row
            if ride.turnLeftCount > 0 || ride.turnRightCount > 0 || ride.brakeCount > 0 {
                HStack(spacing: 16) {
                    if ride.turnLeftCount > 0 {
                        Label("\(ride.turnLeftCount)", systemImage: "arrow.turn.up.left")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    
                    if ride.turnRightCount > 0 {
                        Label("\(ride.turnRightCount)", systemImage: "arrow.turn.up.right")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    
                    if ride.brakeCount > 0 {
                        Label("\(ride.brakeCount)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct RideStatItem: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - InfluxDB Settings View

struct InfluxDBSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var influxDB = InfluxDBService.shared
    
    @State private var url = ""
    @State private var org = ""
    @State private var bucket = ""
    @State private var token = ""
    @State private var showingToken = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("InfluxDB Cloud Configuration")) {
                    TextField("URL (e.g., https://us-east-1-1.aws.cloud2.influxdata.com)", text: $url)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    TextField("Organization", text: $org)
                        .autocapitalization(.none)
                    
                    TextField("Bucket", text: $bucket)
                        .autocapitalization(.none)
                    
                    HStack {
                        if showingToken {
                            TextField("API Token", text: $token)
                                .autocapitalization(.none)
                        } else {
                            SecureField("API Token", text: $token)
                        }
                        
                        Button(action: { showingToken.toggle() }) {
                            Image(systemName: showingToken ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("Status")) {
                    HStack {
                        Text("Connected")
                        Spacer()
                        Image(systemName: influxDB.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(influxDB.isConfigured ? .green : .red)
                    }
                    
                    Text(influxDB.lastUploadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Help")) {
                    Link(destination: URL(string: "https://cloud2.influxdata.com/signup")!) {
                        Label("Sign up for InfluxDB Cloud (Free)", systemImage: "link")
                    }
                    
                    Text("1. Create a free InfluxDB Cloud account\n2. Create a bucket named 'smart-helmet'\n3. Generate an API token with write access\n4. Copy your org URL and credentials here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("InfluxDB Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        influxDB.configure(url: url, org: org, bucket: bucket, token: token)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                url = UserDefaults.standard.string(forKey: "influx_url") ?? ""
                org = UserDefaults.standard.string(forKey: "influx_org") ?? ""
                bucket = UserDefaults.standard.string(forKey: "influx_bucket") ?? ""
                token = UserDefaults.standard.string(forKey: "influx_token") ?? ""
            }
        }
    }
}

#Preview {
    RideHistoryView()
}
