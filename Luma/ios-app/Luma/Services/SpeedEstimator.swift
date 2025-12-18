//
//  SpeedEstimator.swift
//  NavHalo Pilot
//
//  Estimates speed from accelerometer patterns (backup for GPS)
//

import Foundation
import Combine

class SpeedEstimator: ObservableObject {
    @Published var estimatedSpeed: SpeedEstimate = .stopped
    
    private var recentSamples: [IMUSample] = []
    private let maxSamples = 100  // 2 seconds @ 50Hz
    
    // MARK: - Speed Estimation Algorithm
    
    func updateWithSample(_ sample: IMUSample) {
        // Maintain rolling window
        recentSamples.append(sample)
        if recentSamples.count > maxSamples {
            recentSamples.removeFirst()
        }
        
        guard recentSamples.count >= 50 else { return }  // Need at least 1 second
        
        estimatedSpeed = classifySpeed()
    }
    
    private func classifySpeed() -> SpeedEstimate {
        // Extract features from recent IMU data
        let features = extractFeatures()
        
        // Decision tree based on cycling dynamics
        
        // 1. Check for stopped (very low variance + low magnitude)
        if features.accelVariance < 0.05 && features.avgMagnitude < 1.2 {
            return .stopped
        }
        
        // 2. Slow speed (low vibration, moderate variance)
        if features.vibrationFrequency < 2.0 && features.accelVariance < 0.15 {
            return .slow
        }
        
        // 3. Fast speed (high vibration, high gyro activity)
        if features.vibrationFrequency > 5.0 || features.gyroVariance > 150 {
            return .fast
        }
        
        // 4. Moderate speed (default middle range)
        return .moderate
    }
    
    private func extractFeatures() -> SpeedFeatures {
        var features = SpeedFeatures()
        
        // Calculate acceleration magnitude for each sample
        let magnitudes = recentSamples.map { $0.accelMag }
        
        // Average magnitude
        features.avgMagnitude = magnitudes.reduce(0, +) / Float(magnitudes.count)
        
        // Variance (measure of vibration/roughness)
        let avgMag = features.avgMagnitude
        let variance = magnitudes.map { pow($0 - avgMag, 2) }.reduce(0, +) / Float(magnitudes.count)
        features.accelVariance = variance
        
        // Vibration frequency (zero-crossings in acceleration)
        var crossings = 0
        for i in 1..<magnitudes.count {
            if (magnitudes[i] - avgMag) * (magnitudes[i-1] - avgMag) < 0 {
                crossings += 1
            }
        }
        features.vibrationFrequency = Float(crossings) / 2.0  // Approximate Hz
        
        // Gyroscope variance (measure of turning/movement)
        let gyroMagnitudes = recentSamples.map {
            sqrt($0.gyroX * $0.gyroX + $0.gyroY * $0.gyroY + $0.gyroZ * $0.gyroZ)
        }
        let avgGyro = gyroMagnitudes.reduce(0, +) / Float(gyroMagnitudes.count)
        let gyroVar = gyroMagnitudes.map { pow($0 - avgGyro, 2) }.reduce(0, +) / Float(gyroMagnitudes.count)
        features.gyroVariance = gyroVar
        
        return features
    }
    
    // MARK: - Clear Data
    
    func reset() {
        recentSamples.removeAll()
        estimatedSpeed = .stopped
    }
}

// MARK: - Feature Extraction

private struct SpeedFeatures {
    var avgMagnitude: Float = 0.0
    var accelVariance: Float = 0.0
    var vibrationFrequency: Float = 0.0
    var gyroVariance: Float = 0.0
}

// MARK: - Speed Estimate Extension

extension SpeedEstimate {
    var kmhRange: String {
        switch self {
        case .stopped: return "0 km/h"
        case .slow: return "1-10 km/h"
        case .moderate: return "10-20 km/h"
        case .fast: return ">20 km/h"
        }
    }
    
    var icon: String {
        switch self {
        case .stopped: return "hand.raised.fill"
        case .slow: return "tortoise.fill"
        case .moderate: return "bicycle"
        case .fast: return "hare.fill"
        }
    }
}
