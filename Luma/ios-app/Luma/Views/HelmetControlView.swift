//
//  HelmetControlView.swift
//  SmartHelmetApp
//

import SwiftUI

struct HelmetControlView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var leftTurnActive = false
    @State private var rightTurnActive = false
    @State private var showDeviceList = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Connection Status Card
                        connectionStatusCard
                        
                        if bluetoothManager.isConnected {
                            // Helmet Status
                            helmetStatusCard
                            
                            // Turn Signal Controls
                            turnSignalControls
                            
                            // Mode Controls
                            modeControls
                            
                            // Sensor Data
                            sensorDataCard
                        } else {
                            // Scan for devices
                            scanSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            }
            .navigationTitle("Smart Helmet")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(hex: "1a1a2e"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showDeviceList) {
                DeviceListSheet(bluetoothManager: bluetoothManager)
            }
            .alert("ðŸš¨ CRASH DETECTED!", isPresented: $bluetoothManager.showCrashAlert) {
                Button("I'm OK - False Alarm", role: .cancel) {
                    bluetoothManager.confirmFalseAlarm()
                }
            } message: {
                Text("Are you alright? If you don't respond in 30 seconds, emergency services will be notified.")
            }
        }
    }
    
    // MARK: - Connection Status Card
    
    private var connectionStatusCard: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(bluetoothManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bluetoothManager.isConnected ? "Connected" : "Not Connected")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(bluetoothManager.connectionState)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if bluetoothManager.isConnected {
                Button(action: { bluetoothManager.disconnect() }) {
                    Text("Disconnect")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(20)
                }
            } else {
                Button(action: { 
                    if bluetoothManager.isScanning {
                        bluetoothManager.stopScanning()
                    } else {
                        bluetoothManager.startScanning()
                    }
                }) {
                    HStack(spacing: 6) {
                        if bluetoothManager.isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(bluetoothManager.isScanning ? "Scanning..." : "Scan")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(20)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
    
    // MARK: - Helmet Status Card
    
    private var helmetStatusCard: some View {
        VStack(spacing: 16) {
            // Helmet visualization
            ZStack {
                // Helmet shape
                HelmetVisualization(state: bluetoothManager.sensorData.state)
                    .frame(height: 150)
            }
            
            // Current state
            HStack {
                Image(systemName: bluetoothManager.sensorData.state.icon)
                    .font(.title2)
                    .foregroundColor(bluetoothManager.sensorData.state.color)
                
                Text(bluetoothManager.sensorData.state.description)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(bluetoothManager.sensorData.state.color.opacity(0.2))
            .cornerRadius(20)
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
    
    // MARK: - Turn Signal Controls
    
    private var turnSignalControls: some View {
        VStack(spacing: 16) {
            Text("Turn Signals")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                // Left turn
                TurnSignalButton(
                    direction: .left,
                    isActive: leftTurnActive,
                    onPress: {
                        leftTurnActive = true
                        rightTurnActive = false
                        bluetoothManager.turnLeftOn()
                    },
                    onRelease: {
                        leftTurnActive = false
                        bluetoothManager.turnLeftOff()
                    }
                )
                
                // Right turn
                TurnSignalButton(
                    direction: .right,
                    isActive: rightTurnActive,
                    onPress: {
                        rightTurnActive = true
                        leftTurnActive = false
                        bluetoothManager.turnRightOn()
                    },
                    onRelease: {
                        rightTurnActive = false
                        bluetoothManager.turnRightOff()
                    }
                )
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
    
    // MARK: - Mode Controls
    
    private var modeControls: some View {
        VStack(spacing: 16) {
            Text("Modes")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                ModeButton(
                    icon: "bicycle",
                    title: "Normal",
                    isActive: bluetoothManager.sensorData.state == .normal,
                    color: .green
                ) {
                    bluetoothManager.setNormalMode()
                }
                
                ModeButton(
                    icon: "party.popper.fill",
                    title: "Party",
                    isActive: bluetoothManager.sensorData.state == .party,
                    color: .purple
                ) {
                    bluetoothManager.setPartyMode()
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
    
    // MARK: - Sensor Data Card
    
    private var sensorDataCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "sensor.fill")
                    .foregroundColor(.cyan)
                Text("Sensor Data")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                SensorDataItem(
                    icon: "arrow.up.and.down",
                    title: "G-Force",
                    value: bluetoothManager.sensorData.gForceString,
                    color: .orange
                )
                
                SensorDataItem(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Pitch",
                    value: bluetoothManager.sensorData.pitchString,
                    color: .blue
                )
                
                SensorDataItem(
                    icon: "arrow.left.and.right",
                    title: "Roll",
                    value: bluetoothManager.sensorData.rollString,
                    color: .green
                )
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
    
    // MARK: - Scan Section
    
    private var scanSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Connect Your Helmet")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Make sure your Smart Helmet is powered on and nearby")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            if !bluetoothManager.discoveredDevices.isEmpty {
                VStack(spacing: 12) {
                    Text("Found Devices")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                        Button(action: {
                            bluetoothManager.connect(to: device)
                        }) {
                            HStack {
                                Image(systemName: "shield.checkered")
                                    .foregroundColor(.orange)
                                
                                Text(device.name ?? "Unknown Device")
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(40)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }
}

// MARK: - Helmet Visualization

struct HelmetVisualization: View {
    let state: HelmetState
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Helmet shape
            HelmetShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "2d2d2d"), Color(hex: "1a1a1a")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // LED strip
            HelmetLEDStrip(state: state, animationPhase: animationPhase)
                .offset(y: 30)
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }
}

struct HelmetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: width, y: height * 0.6),
            control1: CGPoint(x: width * 0.8, y: 0),
            control2: CGPoint(x: width, y: height * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: height),
            control1: CGPoint(x: width, y: height * 0.9),
            control2: CGPoint(x: width * 0.7, y: height)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: height * 0.6),
            control1: CGPoint(x: width * 0.3, y: height),
            control2: CGPoint(x: 0, y: height * 0.9)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: 0),
            control1: CGPoint(x: 0, y: height * 0.3),
            control2: CGPoint(x: width * 0.2, y: 0)
        )
        
        return path
    }
}

struct HelmetLEDStrip: View {
    let state: HelmetState
    let animationPhase: CGFloat
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(ledColor(for: index))
                    .frame(width: 10, height: 10)
            }
        }
    }
    
    private func ledColor(for index: Int) -> Color {
        switch state {
        case .normal:
            return index >= 4 && index < 8 ? Color.red.opacity(0.8) : Color.red.opacity(0.2)
        case .braking:
            return Color.red
        case .turnLeft:
            let activeIndex = Int(animationPhase * 6) % 6
            return index <= (5 - activeIndex) ? Color.orange : Color.orange.opacity(0.2)
        case .turnRight:
            let activeIndex = Int(animationPhase * 6) % 6
            return index >= (6 + activeIndex) ? Color.orange : Color.orange.opacity(0.2)
        case .crashAlert:
            return animationPhase > 0.5 ? Color.red : Color.white
        case .party:
            let hue = Double(index) / 12.0 + Double(animationPhase)
            return Color(hue: hue.truncatingRemainder(dividingBy: 1.0), saturation: 1, brightness: 1)
        }
    }
}

// MARK: - Turn Signal Button

struct TurnSignalButton: View {
    let direction: TurnDirection
    let isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 12) {
                Image(systemName: direction.icon)
                    .font(.system(size: 40, weight: .bold))
                
                Text(direction.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(isActive ? .black : .orange)
            .frame(width: 120, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isActive ? Color.orange : Color.orange.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.orange, lineWidth: 2)
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isActive { onPress() }
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
}

// MARK: - Mode Button

struct ModeButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundColor(isActive ? .black : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isActive ? color : color.opacity(0.2))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color, lineWidth: 2)
            )
        }
    }
}

// MARK: - Sensor Data Item

struct SensorDataItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Device List Sheet

struct DeviceListSheet: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                Button(action: {
                    bluetoothManager.connect(to: device)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "shield.checkered")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text(device.name ?? "Unknown")
                                .font(.headline)
                            Text(device.identifier.uuidString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HelmetControlView()
        .environmentObject(BluetoothManager())
}
