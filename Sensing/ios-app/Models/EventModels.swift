//
//  EventModels.swift
//  NavHalo Pilot
//
//  Data models for event classification and IMU data
//

import Foundation
import SwiftUI

// MARK: - Event Labels

enum EventLabel: String, CaseIterable, Codable {
    case brake = "brake"
    case crash = "crash"
    case bump = "bump"
    case turn = "turn"
    case normal = "normal"
    case unknown = "unknown"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .brake: return "exclamationmark.octagon.fill"
        case .crash: return "exclamationmark.triangle.fill"
        case .bump: return "wave.3.right"
        case .turn: return "arrow.turn.up.right"
        case .normal: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .brake: return .orange
        case .crash: return .red
        case .bump: return .blue
        case .turn: return .purple
        case .normal: return .green
        case .unknown: return .gray
        }
    }
}

// MARK: - Context Metadata

enum RoadSurface: String, CaseIterable, Codable {
    case smooth = "Smooth"
    case rough = "Rough"
    case cobbles = "Cobbles"
    case gravel = "Gravel"
}

enum WeatherCondition: String, CaseIterable, Codable {
    case dry = "Dry"
    case wet = "Wet"
    case icy = "Icy"
}

enum SpeedEstimate: String, CaseIterable, Codable {
    case stopped = "Stopped"
    case slow = "Slow (<10 km/h)"
    case moderate = "Moderate (10-20 km/h)"
    case fast = "Fast (>20 km/h)"
}

struct EventContext: Codable {
    let roadSurface: RoadSurface
    let weather: WeatherCondition
    let speedEstimate: SpeedEstimate
    let notes: String?
}

// MARK: - IMU Sample

struct IMUSample: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let accelX: Float
    let accelY: Float
    let accelZ: Float
    let gyroX: Float
    let gyroY: Float
    let gyroZ: Float
    
    var accelMag: Float {
        sqrt(accelX*accelX + accelY*accelY + accelZ*accelZ)
    }
    
    enum CodingKeys: String, CodingKey {
        case timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ
    }
}

// MARK: - Event Window

struct EventWindow: Identifiable {
    let id = UUID()
    let timestamp: Date
    let duration: Double
    let samples: [IMUSample]
    let peakAccelMag: Float
    let peakJerk: Float
    let preWindowSamples: [IMUSample]
    let postWindowSamples: [IMUSample]
}

// MARK: - BLE UUIDs

struct NavHaloBLEUUIDs {
    static let serviceUUID = "19B10000-E8F2-537E-4F6C-D104768A1214"
    static let imuCharUUID = "19B10001-E8F2-537E-4F6C-D104768A1214"
    static let commandCharUUID = "19B10002-E8F2-537E-4F6C-D104768A1214"
    static let statusCharUUID = "19B10003-E8F2-537E-4F6C-D104768A1214"
}
