//
//  BLEManager.swift
//  LumaHelmet
//
//  CoreBluetooth service for ESP32 helmet communication - iOS 17+
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Constants
struct BLEConstants {
    static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let imuCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    static let eventCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")
    static let commandCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26aa")
}

// MARK: - Data Models
struct IMUData: Identifiable {
    let id = UUID()
    let accelX: Float
    let accelY: Float
    let accelZ: Float
    let gyroX: Float
    let gyroY: Float
    let gyroZ: Float
    let timestamp: UInt32
    
    var accelMag: Float {
        sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ)
    }
}

enum EventClass: Int, CaseIterable, Codable {
    case brake = 0
    case bump = 1
    case crash = 2
    case normal = 3
    case turn = 4
    
    var name: String {
        switch self {
        case .brake: return "Brake"
        case .bump: return "Bump"
        case .crash: return "Crash"
        case .normal: return "Normal"
        case .turn: return "Turn"
        }
    }
    
    var iconName: String {
        switch self {
        case .brake: return "hand.raised.fill"
        case .bump: return "waveform.path"
        case .crash: return "exclamationmark.triangle.fill"
        case .normal: return "checkmark.circle"
        case .turn: return "arrow.turn.up.right"
        }
    }
    
    var colorName: String {
        switch self {
        case .brake: return "orange"
        case .crash: return "red"
        case .bump: return "yellow"
        case .turn: return "blue"
        case .normal: return "green"
        }
    }
}

struct DetectedEvent: Identifiable, Codable {
    let id: UUID
    let eventClass: EventClass
    let confidence: Float
    let timestamp: Date
    
    init(eventClass: EventClass, confidence: Float, timestamp: Date = Date()) {
        self.id = UUID()
        self.eventClass = eventClass
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - BLE Manager
class BLEManager: NSObject, ObservableObject {
    // Published state
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var latestIMUData: IMUData?
    @Published var detectedEvents: [DetectedEvent] = []
    @Published var showCrashAlert = false
    @Published var currentCrashEvent: DetectedEvent?
    @Published var bluetoothState: CBManagerState = .unknown
    
    // CoreBluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    
    // Callbacks
    var onEventDetected: ((DetectedEvent) -> Void)?
    var onIMUData: ((IMUData) -> Void)?
    
    // Debounce helpers
    private var lastEventInsertTime: Date = .distantPast
    private let minEventInsertInterval: TimeInterval = 0.05 // 50 ms to reduce churn
    private var lastCrashAlertTime: Date = .distantPast
    private let minCrashAlertInterval: TimeInterval = 2.0 // avoid re-triggering alert rapidly
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not ready"
            return
        }
        isScanning = true
        discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(withServices: [BLEConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        connectionStatus = "Scanning..."
        
        // Auto-stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.isScanning == true && self?.isConnected == false {
                self?.stopScanning()
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if !isConnected {
            connectionStatus = "Disconnected"
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionStatus = "Connecting..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - LED Commands
    func sendCommand(_ command: String) {
        guard let peripheral = connectedPeripheral,
              let characteristic = commandCharacteristic,
              let data = command.data(using: .utf8) else {
            print("BLE: Cannot send command - not connected")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("BLE: Sent command: \(command)")
    }
    
    func turnLeftOn() { sendCommand("LEFT_ON") }
    func turnRightOn() { sendCommand("RIGHT_ON") }
    func turnOff() { sendCommand("TURN_OFF") }
    func partyModeOn() { sendCommand("PARTY_ON") }
    func partyModeOff() { sendCommand("PARTY_OFF") }
    
    func dismissCrash() {
        sendCommand("CRASH_DISMISS")
        showCrashAlert = false
        currentCrashEvent = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:
            print("BLE: Powered on")
            connectionStatus = "Ready"
        case .poweredOff:
            connectionStatus = "Bluetooth Off"
            isConnected = false
        case .unauthorized:
            connectionStatus = "Bluetooth Unauthorized"
        case .unsupported:
            connectionStatus = "Bluetooth Unsupported"
        default:
            connectionStatus = "Bluetooth Unavailable"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            print("BLE: Discovered \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BLE: Connected to \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceUUID])
        isConnected = true
        connectionStatus = "Connected"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("BLE: Disconnected")
        connectedPeripheral = nil
        commandCharacteristic = nil
        isConnected = false
        connectionStatus = "Disconnected"
        
        // Auto-reconnect if unexpected disconnect
        if error != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("BLE: Failed to connect: \(error?.localizedDescription ?? "Unknown")")
        connectionStatus = "Connection Failed"
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            // Discover only the characteristics we care about
            if service.uuid == BLEConstants.serviceUUID {
                peripheral.discoverCharacteristics([BLEConstants.imuCharUUID,
                                                    BLEConstants.eventCharUUID,
                                                    BLEConstants.commandCharUUID], for: service)
            } else {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEConstants.imuCharUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                print("BLE: Subscribed to IMU data")
                
            case BLEConstants.eventCharUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                print("BLE: Subscribed to events")
                
            case BLEConstants.commandCharUUID:
                commandCharacteristic = characteristic
                print("BLE: Command characteristic ready")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("BLE: Update error for \(characteristic.uuid): \(error.localizedDescription)")
        }
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case BLEConstants.imuCharUUID:
            parseIMUData(data)
        case BLEConstants.eventCharUUID:
            parseEventData(data)
        default:
            break
        }
    }
    
    // MARK: - Safe Data Parsing
    private func parseIMUData(_ data: Data) {
        // Expect exactly 28 bytes: 6 floats (24) + 1 uint32 timestamp (4)
        guard data.count == 28 else {
            print("BLE IMU: Unexpected length \(data.count), expected 28. Dropping packet.")
            return
        }
        
        func readUInt32LE(from range: Range<Int>) -> UInt32? {
            guard range.upperBound <= data.count else { return nil }
            var tmp = [UInt8](repeating: 0, count: 4)
            data[range].copyBytes(to: &tmp, count: 4)
            let u = UInt32(tmp[0]) | (UInt32(tmp[1]) << 8) | (UInt32(tmp[2]) << 16) | (UInt32(tmp[3]) << 24)
            return UInt32(littleEndian: u)
        }
        
        func readFloatLE(from range: Range<Int>) -> Float? {
            guard let u = readUInt32LE(from: range) else { return nil }
            return Float(bitPattern: u)
        }
        
        guard
            let ax = readFloatLE(from: 0..<4),
            let ay = readFloatLE(from: 4..<8),
            let az = readFloatLE(from: 8..<12),
            let gx = readFloatLE(from: 12..<16),
            let gy = readFloatLE(from: 16..<20),
            let gz = readFloatLE(from: 20..<24),
            let ts = readUInt32LE(from: 24..<28)
        else {
            print("BLE IMU: Failed to parse floats/timestamp safely. Dropping packet.")
            return
        }
        
        let imu = IMUData(
            accelX: ax,
            accelY: ay,
            accelZ: az,
            gyroX:  gx,
            gyroY:  gy,
            gyroZ:  gz,
            timestamp: ts
        )
        
        DispatchQueue.main.async {
            self.latestIMUData = imu
            self.onIMUData?(imu)
        }
    }
    
    private func parseEventData(_ data: Data) {
        // Expect exactly 5 bytes: class (1) + confidence float (4)
        guard data.count >= 5 else {
            print("BLE Event: Unexpected length \(data.count), expected >=5. Dropping packet.")
            return
        }
        
        // Class byte
        let classRaw = Int(data[0])
        
        // Safe float read (little-endian) from bytes 1..<5
        var tmp = [UInt8](repeating: 0, count: 4)
        data[1..<min(5, data.count)].copyBytes(to: &tmp, count: 4)
        let u = UInt32(tmp[0]) | (UInt32(tmp[1]) << 8) | (UInt32(tmp[2]) << 16) | (UInt32(tmp[3]) << 24)
        let confidence = Float(bitPattern: UInt32(littleEndian: u))
        
        guard let eventClass = EventClass(rawValue: classRaw) else {
            print("BLE Event: Unknown class \(classRaw)")
            return
        }
        
        // Debounce event insertion to avoid rapid UI churn
        let now = Date()
        if now.timeIntervalSince(lastEventInsertTime) < minEventInsertInterval {
            // Too soon; coalesce
            print("BLE Event: Coalescing frequent events.")
        } else {
            lastEventInsertTime = now
        }
        
        let event = DetectedEvent(eventClass: eventClass, confidence: confidence)
        
        DispatchQueue.main.async {
            // Insert at front, keep capped
            self.detectedEvents.insert(event, at: 0)
            if self.detectedEvents.count > 100 {
                self.detectedEvents = Array(self.detectedEvents.prefix(100))
            }
            
            // Crash alert: only trigger if not already visible and not re-triggering too fast
            if eventClass == .crash {
                let shouldShow =
                    !self.showCrashAlert &&
                    now.timeIntervalSince(self.lastCrashAlertTime) >= self.minCrashAlertInterval
                if shouldShow {
                    self.currentCrashEvent = event
                    self.showCrashAlert = true
                    self.lastCrashAlertTime = now
                } else {
                    print("BLE Event: Crash alert suppressed (already showing or debounced).")
                }
            }
            
            self.onEventDetected?(event)
        }
        
        print("BLE Event: \(eventClass.name) (confidence: \(String(format: "%.2f", confidence)))")
    }
}
