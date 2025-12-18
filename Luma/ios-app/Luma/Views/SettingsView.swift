//
//  SettingsView.swift
//  SmartHelmetApp
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("crashDetectionEnabled") private var crashDetectionEnabled = true
    @AppStorage("autoConnectEnabled") private var autoConnectEnabled = true
    @AppStorage("brakeThreshold") private var brakeThreshold = 0.5
    @AppStorage("crashThreshold") private var crashThreshold = 4.0
    @AppStorage("emergencyContactName") private var emergencyContactName = ""
    @AppStorage("emergencyContactPhone") private var emergencyContactPhone = ""
    @AppStorage("temperatureUnit") private var temperatureUnit = "celsius"
    @AppStorage("distanceUnit") private var distanceUnit = "km"
    
    @State private var showResetAlert = false
    
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
                
                List {
                    // Helmet Settings
                    Section {
                        Toggle(isOn: $crashDetectionEnabled) {
                            SettingRow(
                                icon: "exclamationmark.triangle.fill",
                                title: "Crash Detection",
                                subtitle: "Alert when high G-force detected",
                                color: .red
                            )
                        }
                        .tint(.orange)
                        
                        Toggle(isOn: $autoConnectEnabled) {
                            SettingRow(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "Auto-Connect",
                                subtitle: "Automatically connect to helmet",
                                color: .blue
                            )
                        }
                        .tint(.orange)
                    } header: {
                        Text("Helmet")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    
                    // Sensitivity Settings
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow(
                                icon: "gauge.medium",
                                title: "Brake Sensitivity",
                                subtitle: "G-force threshold: \(String(format: "%.1f", brakeThreshold))G",
                                color: .orange
                            )
                            
                            Slider(value: $brakeThreshold, in: 0.2...1.0, step: 0.1)
                                .tint(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow(
                                icon: "bolt.fill",
                                title: "Crash Threshold",
                                subtitle: "G-force threshold: \(String(format: "%.1f", crashThreshold))G",
                                color: .red
                            )
                            
                            Slider(value: $crashThreshold, in: 2.0...8.0, step: 0.5)
                                .tint(.red)
                        }
                    } header: {
                        Text("Sensitivity")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    
                    // Emergency Contact
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow(
                                icon: "person.fill",
                                title: "Contact Name",
                                subtitle: emergencyContactName.isEmpty ? "Not set" : emergencyContactName,
                                color: .green
                            )
                            
                            TextField("Name", text: $emergencyContactName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow(
                                icon: "phone.fill",
                                title: "Phone Number",
                                subtitle: emergencyContactPhone.isEmpty ? "Not set" : emergencyContactPhone,
                                color: .green
                            )
                            
                            TextField("Phone", text: $emergencyContactPhone)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.phonePad)
                        }
                    } header: {
                        Text("Emergency Contact")
                            .foregroundColor(.white.opacity(0.7))
                    } footer: {
                        Text("This contact will be notified if a crash is detected and you don't respond within 30 seconds.")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    
                    // Units
                    Section {
                        Picker(selection: $temperatureUnit) {
                            Text("Celsius (Â°C)").tag("celsius")
                            Text("Fahrenheit (Â°F)").tag("fahrenheit")
                        } label: {
                            SettingRow(
                                icon: "thermometer",
                                title: "Temperature",
                                subtitle: temperatureUnit == "celsius" ? "Celsius" : "Fahrenheit",
                                color: .cyan
                            )
                        }
                        
                        Picker(selection: $distanceUnit) {
                            Text("Kilometers").tag("km")
                            Text("Miles").tag("mi")
                        } label: {
                            SettingRow(
                                icon: "ruler",
                                title: "Distance",
                                subtitle: distanceUnit == "km" ? "Kilometers" : "Miles",
                                color: .purple
                            )
                        }
                    } header: {
                        Text("Units")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    
                    // About
                    Section {
                        NavigationLink {
                            AboutView()
                        } label: {
                            SettingRow(
                                icon: "info.circle.fill",
                                title: "About",
                                subtitle: "Version 1.0.0",
                                color: .gray
                            )
                        }
                        
                        Button(action: { showResetAlert = true }) {
                            SettingRow(
                                icon: "arrow.counterclockwise",
                                title: "Reset Settings",
                                subtitle: "Restore default values",
                                color: .red
                            )
                        }
                    } header: {
                        Text("App")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(hex: "1a1a2e"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Reset Settings?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("This will restore all settings to their default values.")
            }
        }
    }
    
    private func resetSettings() {
        crashDetectionEnabled = true
        autoConnectEnabled = true
        brakeThreshold = 0.5
        crashThreshold = 4.0
        temperatureUnit = "celsius"
        distanceUnit = "km"
    }
}

// MARK: - Setting Row

struct SettingRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 30)
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    VStack(spacing: 8) {
                        Text("Smart Helmet")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Version 1.0.0")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        FeatureRow(icon: "exclamationmark.triangle.fill", title: "Crash Detection", description: "Automatic crash detection with emergency alerts")
                        FeatureRow(icon: "car.rear.fill", title: "Brake Light", description: "Automatic brake light when decelerating")
                        FeatureRow(icon: "arrow.left.arrow.right", title: "Turn Signals", description: "Easy-to-use turn signal controls")
                        FeatureRow(icon: "cloud.sun.fill", title: "Weather", description: "Weather-based clothing recommendations")
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                    .padding(.horizontal)
                    
                    Spacer(minLength: 100)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    SettingsView()
}
