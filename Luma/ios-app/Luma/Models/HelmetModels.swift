//
//  HelmetModels.swift
//  SmartHelmetApp
//

import Foundation
import SwiftUI

// MARK: - Helmet State
enum HelmetState: Int {
    case normal = 0
    case braking = 1
    case turnLeft = 2
    case turnRight = 3
    case crashAlert = 4
    case party = 5
    
    var description: String {
        switch self {
        case .normal: return "Normal"
        case .braking: return "Braking"
        case .turnLeft: return "Turn Left"
        case .turnRight: return "Turn Right"
        case .crashAlert: return "CRASH ALERT"
        case .party: return "Party Mode"
        }
    }
    
    var stringValue: String {
        switch self {
        case .normal: return "normal"
        case .braking: return "braking"
        case .turnLeft: return "turn_left"
        case .turnRight: return "turn_right"
        case .crashAlert: return "crash_alert"
        case .party: return "party"
        }
    }
    
    var icon: String {
        switch self {
        case .normal: return "bicycle"
        case .braking: return "exclamationmark.octagon.fill"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .crashAlert: return "exclamationmark.triangle.fill"
        case .party: return "party.popper.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .normal: return .green
        case .braking: return .red
        case .turnLeft: return .orange
        case .turnRight: return .orange
        case .crashAlert: return .red
        case .party: return .purple
        }
    }
}

// MARK: - BLE Commands
enum HelmetCommand: UInt8 {
    case turnLeftOn = 0x01
    case turnLeftOff = 0x02
    case turnRightOn = 0x03
    case turnRightOff = 0x04
    case crashFalseAlarm = 0x05
    case partyMode = 0x06
    case normalMode = 0x07
}

// MARK: - Sensor Data
struct HelmetSensorData {
    var gForce: Float = 0.0
    var pitch: Float = 0.0
    var roll: Float = 0.0
    var state: HelmetState = .normal
    var batteryLevel: Int = 100
    var isConnected: Bool = false
    
    // Raw acceleration data (for InfluxDB)
    var accelerationX: Double = 0.0
    var accelerationY: Double = 0.0
    var accelerationZ: Double = 0.0
    
    var gForceString: String {
        String(format: "%.2f G", gForce)
    }
    
    var pitchString: String {
        String(format: "%.1fÂ°", pitch)
    }
    
    var rollString: String {
        String(format: "%.1fÂ°", roll)
    }
}

// MARK: - Ride Data
struct RideData: Identifiable, Codable {
    let id: UUID
    var date: Date
    var duration: TimeInterval
    var distance: Double
    var averageSpeed: Double
    var maxSpeed: Double
    var brakeCount: Int
    var crashDetected: Bool
    
    init(id: UUID = UUID(), date: Date = Date(), duration: TimeInterval = 0, distance: Double = 0, averageSpeed: Double = 0, maxSpeed: Double = 0, brakeCount: Int = 0, crashDetected: Bool = false) {
        self.id = id
        self.date = date
        self.duration = duration
        self.distance = distance
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.brakeCount = brakeCount
        self.crashDetected = crashDetected
    }
    
    var durationString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var distanceString: String {
        String(format: "%.2f km", distance)
    }
}

// MARK: - BLE UUIDs
struct HelmetBLEUUIDs {
    static let serviceUUID = "19B10000-E8F2-537E-4F6C-D104768A1214"
    static let sensorCharUUID = "19B10001-E8F2-537E-4F6C-D104768A1214"
    static let commandCharUUID = "19B10002-E8F2-537E-4F6C-D104768A1214"
    static let crashCharUUID = "19B10003-E8F2-537E-4F6C-D104768A1214"
}

// MARK: - Turn Direction (shared across app)
enum TurnDirection {
    case left
    case right
    
    var icon: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        }
    }
    
    var title: String {
        switch self {
        case .left: return "LEFT"
        case .right: return "RIGHT"
        }
    }
}
