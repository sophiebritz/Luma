//
//  SettingsView.swift
//  LumaHelmet
//
//  App settings and configuration - iOS 17+
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var rideService: RideService
    
    @AppStorage("emergencyContact") private var emergencyContact = ""
    @AppStorage("emergencyName") private var emergencyName = ""
    @AppStorage("crashCountdown") private var crashCountdown = 30
    @AppStorage("turnAutoOffDistance") private var turnAutoOffDistance = 20.0
    
    var body: some View {
        NavigationStack {
            Form {
                // Helmet section
                Section("Helmet") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(bleManager.connectionStatus)
                            .foregroundStyle(bleManager.isConnected ? .green : .secondary)
                    }
                    
                    if bleManager.isConnected {
                        Button("Disconnect Helmet", role: .destructive) {
                            bleManager.disconnect()
                        }
                    } else {
                        Text("Connect from Home tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Emergency contact section
                Section {
                    TextField("Contact Name", text: $emergencyName)
                        .textContentType(.name)
                    
                    TextField("Phone Number", text: $emergencyContact)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    
                    Stepper("Alert Countdown: \(crashCountdown)s", value: $crashCountdown, in: 10...60, step: 5)
                } header: {
                    Text("Emergency Contact")
                } footer: {
                    Text("This contact will be called if a crash is detected and not dismissed within the countdown.")
                }
                
                // Turn indicators section
                Section {
                    HStack {
                        Text("Auto-off Distance")
                        Spacer()
                        Text("\(Int(turnAutoOffDistance))m")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $turnAutoOffDistance, in: 10...50, step: 5)
                } header: {
                    Text("Turn Indicators")
                } footer: {
                    Text("Turn signals automatically deactivate after passing the turn by this distance.")
                }
                
                // Data section
                Section("Data") {
                    HStack {
                        Text("Saved Rides")
                        Spacer()
                        Text("\(rideService.rideHistory.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Clear All Ride History", role: .destructive) {
                        rideService.clearAllHistory()
                    }
                    .disabled(rideService.rideHistory.isEmpty)
                }
                
                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("iOS")
                        Spacer()
                        Text("\(UIDevice.current.systemVersion)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/luma-helmet")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(BLEManager())
        .environmentObject(RideService())
}

