//
//  BluetoothManager.swift
//  SmartHelmetApp
//

import Foundation
import Combine
import CoreBluetooth
import SwiftUI

class BluetoothManager: NSObject, ObservableObject {
    // Published properties for UI binding
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionState: String = "Disconnected"
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var sensorData = HelmetSensorData()
    @Published var crashAlertActive = false
    @Published var showCrashAlert = false
    
    // Core Bluetooth objects
    private var centralManager: CBCentralManager!
    private(set) var helmetPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var sensorCharacteristic: CBCharacteristic?
    private var crashCharacteristic: CBCharacteristic?
    
    // UUIDs
    private let serviceUUID = CBUUID(string: HelmetBLEUUIDs.serviceUUID)
    private let sensorCharUUID = CBUUID(string: HelmetBLEUUIDs.sensorCharUUID)
    private let commandCharUUID = CBUUID(string: HelmetBLEUUIDs.commandCharUUID)
    private let crashCharUUID = CBUUID(string: HelmetBLEUUIDs.crashCharUUID)
    
    // Crash alert timer
    private var crashTimer: Timer?
    private let crashConfirmationTime: TimeInterval = 30.0
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = "Bluetooth not available"
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll()
        connectionState = "Scanning..."
        
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if !isConnected {
            connectionState = "Scan complete"
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        helmetPeripheral = peripheral
        connectionState = "Connecting..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = helmetPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - Helmet Commands
    
    func sendCommand(_ command: HelmetCommand) {
        guard let characteristic = commandCharacteristic,
              let peripheral = helmetPeripheral else {
            print("Cannot send command - not connected")
            return
        }
        
        let data = Data([command.rawValue])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }
    
    func turnLeftOn() {
        sendCommand(.turnLeftOn)
        sensorData.state = .turnLeft
    }
    
    func turnLeftOff() {
        sendCommand(.turnLeftOff)
        sensorData.state = .normal
    }
    
    func turnRightOn() {
        sendCommand(.turnRightOn)
        sensorData.state = .turnRight
    }
    
    func turnRightOff() {
        sendCommand(.turnRightOff)
        sensorData.state = .normal
    }
    
    func setPartyMode() {
        sendCommand(.partyMode)
        sensorData.state = .party
    }
    
    func setNormalMode() {
        sendCommand(.normalMode)
        sensorData.state = .normal
    }
    
    func confirmFalseAlarm() {
        sendCommand(.crashFalseAlarm)
        crashAlertActive = false
        showCrashAlert = false
        crashTimer?.invalidate()
        sensorData.state = .normal
    }
    
    // MARK: - Crash Alert Handling
    
    private func handleCrashAlert() {
        crashAlertActive = true
        showCrashAlert = true
        sensorData.state = .crashAlert
        
        // Start countdown timer
        crashTimer?.invalidate()
        crashTimer = Timer.scheduledTimer(withTimeInterval: crashConfirmationTime, repeats: false) { [weak self] _ in
            self?.triggerEmergencyResponse()
        }
        
        // Vibrate and play sound
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
    
    private func triggerEmergencyResponse() {
        // TODO: Send emergency notification to contacts
        // TODO: Send location to emergency services
        print("EMERGENCY: No response from rider - triggering emergency protocol")
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionState = "Ready to scan"
        case .poweredOff:
            connectionState = "Bluetooth is off"
        case .unauthorized:
            connectionState = "Bluetooth unauthorized"
        case .unsupported:
            connectionState = "Bluetooth not supported"
        case .resetting:
            connectionState = "Bluetooth resetting"
        case .unknown:
            connectionState = "Bluetooth state unknown"
        @unknown default:
            connectionState = "Unknown state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            
            // Auto-connect if it's our helmet
            if peripheral.name == "SmartHelmet" {
                connect(to: peripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionState = "Connected"
        sensorData.isConnected = true
        stopScanning()
        
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionState = "Connection failed"
        sensorData.isConnected = false
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionState = "Disconnected"
        sensorData.isConnected = false
        helmetPeripheral = nil
        commandCharacteristic = nil
        sensorCharacteristic = nil
        crashCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([sensorCharUUID, commandCharUUID, crashCharUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case sensorCharUUID:
                sensorCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                
            case commandCharUUID:
                commandCharacteristic = characteristic
                
            case crashCharUUID:
                crashCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == sensorCharUUID {
            parseSensorData(data)
        } else if characteristic.uuid == crashCharUUID {
            if data.first == 0x01 {
                DispatchQueue.main.async { [weak self] in
                    self?.handleCrashAlert()
                }
            }
        }
    }
    
    private func parseSensorData(_ data: Data) {
        guard data.count >= 13 else { return }
        
        DispatchQueue.main.async { [weak self] in
            // Parse state (1 byte)
            let stateValue = Int(data[0])
            self?.sensorData.state = HelmetState(rawValue: stateValue) ?? .normal
            
            // Parse G-force (4 bytes float)
            let gForceData = data.subdata(in: 1..<5)
            self?.sensorData.gForce = gForceData.withUnsafeBytes { $0.load(as: Float.self) }
            
            // Parse pitch (4 bytes float)
            let pitchData = data.subdata(in: 5..<9)
            self?.sensorData.pitch = pitchData.withUnsafeBytes { $0.load(as: Float.self) }
            
            // Parse roll (4 bytes float)
            let rollData = data.subdata(in: 9..<13)
            self?.sensorData.roll = rollData.withUnsafeBytes { $0.load(as: Float.self) }
        }
    }
}
