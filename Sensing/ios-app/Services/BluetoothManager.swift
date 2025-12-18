//
//  BluetoothManager.swift
//  NavHalo Pilot
//
//  Manages BLE connection to ESP32-C3 helmet
//

import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var peripherals: [CBPeripheral] = []
    @Published var latestIMUSample: IMUSample?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    private var imuCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: NavHaloBLEUUIDs.serviceUUID)
    private let imuCharUUID = CBUUID(string: NavHaloBLEUUIDs.imuCharUUID)
    private let commandCharUUID = CBUUID(string: NavHaloBLEUUIDs.commandCharUUID)
    private let statusCharUUID = CBUUID(string: NavHaloBLEUUIDs.statusCharUUID)
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("⚠️ Bluetooth not ready")
            return
        }
        
        peripherals.removeAll()
        isScanning = true
        
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        print("🔍 Scanning for NavHalo helmet...")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("⏹️ Scanning stopped")
    }
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        print("📡 Connecting to \(peripheral.name ?? "Unknown")...")
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        print("🔌 Disconnecting...")
    }
    
    func sendCommand(_ command: UInt8) {
        guard let characteristic = commandCharacteristic,
              let peripheral = connectedPeripheral else {
            print("⚠️ Cannot send command - not connected")
            return
        }
        
        let data = Data([command])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("📤 Sent command: 0x\(String(format: "%02X", command))")
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ Bluetooth is ready")
        case .poweredOff:
            print("❌ Bluetooth is off")
        case .unsupported:
            print("❌ Bluetooth not supported")
        case .unauthorized:
            print("⚠️ Bluetooth not authorized")
        default:
            print("⚠️ Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any],
                       rssi RSSI: NSNumber) {
        
        if !peripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            peripherals.append(peripheral)
            print("🔍 Found: \(peripheral.name ?? "Unknown") (RSSI: \(RSSI))")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.name ?? "Unknown")")
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Disconnected")
        isConnected = false
        connectedPeripheral = nil
        imuCharacteristic = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
    }
    
    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        isConnected = false
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                print("📋 Discovered NavHalo service")
                peripheral.discoverCharacteristics(
                    [imuCharUUID, commandCharUUID, statusCharUUID],
                    for: service
                )
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case imuCharUUID:
                imuCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ IMU characteristic ready")
                
            case commandCharUUID:
                commandCharacteristic = characteristic
                print("✅ Command characteristic ready")
                
            case statusCharUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ Status characteristic ready")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == imuCharUUID {
            parseIMUData(data)
        } else if characteristic.uuid == statusCharUUID {
            if let status = String(data: data, encoding: .utf8) {
                print("📱 Status: \(status)")
            }
        }
    }
    
    // MARK: - Data Parsing
    
    private func parseIMUData(_ data: Data) {
        // Expected format: [timestamp(4)][accelX(4)][accelY(4)][accelZ(4)][gyroX(4)][gyroY(4)][gyroZ(4)]
        guard data.count == 28 else {
            print("⚠️ Invalid IMU data size: \(data.count)")
            return
        }
        
        let timestamp = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let accelX = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let accelY = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        let accelZ = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Float.self) }
        let gyroX = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: Float.self) }
        let gyroY = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: Float.self) }
        let gyroZ = data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: Float.self) }
        
        let sample = IMUSample(
            timestamp: Date(),
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ,
            gyroX: gyroX,
            gyroY: gyroY,
            gyroZ: gyroZ
        )
        
        DispatchQueue.main.async {
            self.latestIMUSample = sample
        }
    }
}

// MARK: - BLE Commands

extension BluetoothManager {
    static let CMD_START_RECORDING: UInt8 = 0x01
    static let CMD_STOP_RECORDING: UInt8 = 0x02
    static let CMD_LED_BRAKE_ON: UInt8 = 0x03
    static let CMD_LED_BRAKE_OFF: UInt8 = 0x04
    static let CMD_LED_CRASH_ON: UInt8 = 0x05
    static let CMD_LED_CRASH_OFF: UInt8 = 0x06
    static let CMD_LED_LEFT_ON: UInt8 = 0x07
    static let CMD_LED_LEFT_OFF: UInt8 = 0x08
    static let CMD_LED_RIGHT_ON: UInt8 = 0x09
    static let CMD_LED_RIGHT_OFF: UInt8 = 0x0A
}
