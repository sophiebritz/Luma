//
//  EventClassificationView.swift
//  NavHalo Pilot
//
//  Main data collection interface
//

import SwiftUI

struct EventClassificationView: View {
    
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var eventDetector = EventDetectionService()
    @StateObject private var dataService = DataCollectionService()
    
    @State private var showingScanner = false
    @State private var showingClassificationSheet = false
    @State private var currentEvent: EventWindow?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 1. Connection Card
                    ConnectionCard(
                        isConnected: bluetoothManager.isConnected,
                        onScanTapped: { showingScanner = true }
                    )
                    
                    // 2. Recording Card
                    RecordingCard(
                        isRecording: dataService.isRecording,
                        duration: dataService.sessionDuration,
                        eventCount: dataService.brakeCount + dataService.crashCount + 
                                   dataService.bumpCount + dataService.normalCount,
                        onRecordTapped: toggleRecording
                    )
                    
                    // 3. Event Detection Card
                    EventDetectionCard(
                        accelMag: eventDetector.currentAccelMag,
                        jerk: eventDetector.currentJerk,
                        isCapturing: eventDetector.isCapturing
                    )
                    
                    // 4. Manual Event Buttons
                    ManualEventCard(
                        onBrakeTest: { eventDetector.manualTrigger() },
                        onCrashTest: { eventDetector.manualTrigger() },
                        onBumpTest: { eventDetector.manualTrigger() }
                    )
                    
                    // 5. Session Statistics
                    StatisticsCard(
                        brakeCount: dataService.brakeCount,
                        crashCount: dataService.crashCount,
                        bumpCount: dataService.bumpCount,
                        normalCount: dataService.normalCount,
                        uploadStatus: dataService.uploadStatus
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("NavHalo Pilot")
            .sheet(isPresented: $showingScanner) {
                ScannerSheet(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: $showingClassificationSheet) {
                if let event = currentEvent {
                    EventClassificationSheet(eventWindow: event) { label, context in
                        dataService.saveClassifiedEvent(event, label: label, context: context)
                    }
                }
            }
            .onReceive(bluetoothManager.$latestIMUSample) { sample in
                if let sample = sample {
                    eventDetector.processSample(sample)
                }
            }
            .onReceive(eventDetector.$detectedEvent) { event in
                if let event = event {
                    currentEvent = event
                    showingClassificationSheet = true
                }
            }
        }
    }
    
    private func toggleRecording() {
        if dataService.isRecording {
            dataService.stopSession()
            bluetoothManager.sendCommand(BluetoothManager.CMD_STOP_RECORDING)
        } else {
            dataService.startSession()
            bluetoothManager.sendCommand(BluetoothManager.CMD_START_RECORDING)
        }
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let isConnected: Bool
    let onScanTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                Text("Connection")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }
            
            if isConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected to helmet")
                    Spacer()
                    Text("IMU sampling at 50 Hz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: onScanTapped) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Scan for Helmet")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Recording Card

struct RecordingCard: View {
    let isRecording: Bool
    let duration: TimeInterval
    let eventCount: Int
    let onRecordTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "record.circle")
                    .font(.title2)
                    .foregroundColor(isRecording ? .red : .gray)
                Text("Recording")
                    .font(.headline)
                Spacer()
                if isRecording {
                    Text(formatDuration(duration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
            
            Button(action: onRecordTapped) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                        .font(.title)
                        .foregroundColor(isRecording ? .red : .orange)
                    
                    VStack(alignment: .leading) {
                        Text(isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                        Text("\(eventCount) events labeled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Event Detection Card

struct EventDetectionCard: View {
    let accelMag: Float
    let jerk: Float
    let isCapturing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                Text("Event Detection")
                    .font(.headline)
                Spacer()
                if isCapturing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Capturing")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("G-Force")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2fg", accelMag))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(accelMag > 1.5 ? .orange : .primary)
                    
                    // Threshold indicator
                    if accelMag > 1.5 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                
                ProgressView(value: min(Double(accelMag), 8.0), total: 8.0)
                    .tint(accelMag > 4.0 ? .red : (accelMag > 1.5 ? .orange : .blue))
                
                HStack {
                    Text("Jerk")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", jerk))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(jerk > 5.0 ? .orange : .primary)
                    
                    if jerk > 5.0 {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                    }
                }
                
                ProgressView(value: min(Double(jerk), 20.0), total: 20.0)
                    .tint(jerk > 10.0 ? .red : (jerk > 5.0 ? .orange : .cyan))
            }
            
            Text(isCapturing ? "📹 Capturing event window..." : "👁️ Monitoring for spikes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Manual Event Card

struct ManualEventCard: View {
    let onBrakeTest: () -> Void
    let onCrashTest: () -> Void
    let onBumpTest: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.tap")
                    .font(.title2)
                Text("Manual Triggers")
                    .font(.headline)
            }
            
            HStack(spacing: 12) {
                ManualButton(
                    title: "Brake Test",
                    icon: "exclamationmark.octagon",
                    color: .orange,
                    action: onBrakeTest
                )
                
                ManualButton(
                    title: "Crash Test",
                    icon: "exclamationmark.triangle",
                    color: .red,
                    action: onCrashTest
                )
                
                ManualButton(
                    title: "Bump Test",
                    icon: "wave.3.right",
                    color: .blue,
                    action: onBumpTest
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ManualButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
        }
    }
}

// MARK: - Statistics Card

struct StatisticsCard: View {
    let brakeCount: Int
    let crashCount: Int
    let bumpCount: Int
    let normalCount: Int
    let uploadStatus: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar")
                    .font(.title2)
                Text("Session Statistics")
                    .font(.headline)
                Spacer()
                if !uploadStatus.isEmpty {
                    Text(uploadStatus)
                        .font(.caption)
                }
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatBadge(label: "Brakes", count: brakeCount, color: .orange)
                StatBadge(label: "Crashes", count: crashCount, color: .red)
                StatBadge(label: "Bumps", count: bumpCount, color: .blue)
                StatBadge(label: "Normal", count: normalCount, color: .green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(color)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Scanner Sheet

struct ScannerSheet: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if bluetoothManager.peripherals.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Scanning for NavHalo helmet...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                        Button {
                            bluetoothManager.connect(to: peripheral)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "bicycle")
                                VStack(alignment: .leading) {
                                    Text(peripheral.name ?? "Unknown")
                                        .font(.headline)
                                    Text(peripheral.identifier.uuidString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Available Helmets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bluetoothManager.stopScanning()
                        dismiss()
                    }
                }
            }
            .onAppear {
                bluetoothManager.startScanning()
            }
            .onDisappear {
                bluetoothManager.stopScanning()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    EventClassificationView()
}
