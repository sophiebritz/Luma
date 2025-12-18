//
//  EventDetectionService.swift
//  NavHalo Pilot
//
//  Auto-detects events and auto-populates context (speed, weather)
//

import Foundation
import SwiftUI
import Combine

class EventDetectionService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentGForce: Float = 0.0
    @Published var currentJerk: Float = 0.0
    @Published var isCapturing: Bool = false
    @Published var detectedEvent: EventWindow?
    
    // MARK: - Detection Configuration
    
    private let accelThreshold: Float = 1.5  // G-force threshold
    private let jerkThreshold: Float = 5.0   // Jerk threshold
    private let captureWindowSeconds: Double = 3.0
    private let preBufferSeconds: Double = 0.5
    private let postBufferSeconds: Double = 0.5
    
    // MARK: - Data Buffers
    
    private var preBuffer: [IMUSample] = []
    private let preBufferSize = 25  // 500ms @ 50Hz
    
    private var captureBuffer: [IMUSample] = []
    private var isInCaptureWindow = false
    private var captureStartTime: Date?
    
    private var lastMagnitude: Float = 0.0
    private var lastSampleTime: Date = Date()
    
    // MARK: - Dependencies
    
    private let locationService: LocationService
    private let weatherService: WeatherService
    private let speedEstimator: SpeedEstimator
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(locationService: LocationService,
         weatherService: WeatherService,
         speedEstimator: SpeedEstimator) {
        self.locationService = locationService
        self.weatherService = weatherService
        self.speedEstimator = speedEstimator
    }
    
    // MARK: - Event Detection
    
    func processSample(_ sample: IMUSample) {
        // Update speed estimator
        speedEstimator.updateWithSample(sample)
        
        // Maintain pre-buffer (rolling window)
        preBuffer.append(sample)
        if preBuffer.count > preBufferSize {
            preBuffer.removeFirst()
        }
        
        // Calculate jerk (change in acceleration)
        let dt = sample.timestamp.timeIntervalSince(lastSampleTime)
        if dt > 0 {
            currentJerk = abs(sample.accelMag - lastMagnitude) / Float(dt)
        }
        
        currentGForce = sample.accelMag
        lastMagnitude = sample.accelMag
        lastSampleTime = sample.timestamp
        
        // Check for event trigger
        if !isInCaptureWindow {
            if sample.accelMag > accelThreshold || currentJerk > jerkThreshold {
                startCapture(triggeredBy: sample)
            }
        } else {
            // Continue capturing
            captureBuffer.append(sample)
            
            // Check if capture window is complete
            if let startTime = captureStartTime,
               sample.timestamp.timeIntervalSince(startTime) >= captureWindowSeconds {
                completeCapture()
            }
        }
    }
    
    private func startCapture(triggeredBy sample: IMUSample) {
        isInCaptureWindow = true
        isCapturing = true
        captureStartTime = sample.timestamp
        
        // Initialize capture buffer with pre-buffer
        captureBuffer = preBuffer
        captureBuffer.append(sample)
        
        // Trigger haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        
        print("🎯 Event detected! G-force: \(sample.accelMag)g, Jerk: \(currentJerk)")
    }
    
    private func completeCapture() {
        guard let startTime = captureStartTime else { return }
        
        // Calculate statistics
        let magnitudes = captureBuffer.map { $0.accelMag }
        let peakAccel = magnitudes.max() ?? 0
        
        // Calculate jerk from sample-to-sample changes
        var jerks: [Float] = []
        for i in 1..<captureBuffer.count {
            let dt = captureBuffer[i].timestamp.timeIntervalSince(captureBuffer[i-1].timestamp)
            if dt > 0 {
                let jerk = abs(captureBuffer[i].accelMag - captureBuffer[i-1].accelMag) / Float(dt)
                jerks.append(jerk)
            }
        }
        let peakJerk = jerks.max() ?? 0
        
        // Capture post-buffer (continue sampling for 500ms)
        // In real implementation, this would happen asynchronously
        let postBuffer: [IMUSample] = []  // Simplified for now
        
        // Create event window
        let event = EventWindow(
            timestamp: startTime,
            duration: captureWindowSeconds,
            samples: captureBuffer,
            peakAccelMag: peakAccel,
            peakJerk: peakJerk,
            preWindowSamples: preBuffer,
            postWindowSamples: postBuffer
        )
        
        // Publish event for classification
        detectedEvent = event
        
        // Reset capture state
        isInCaptureWindow = false
        isCapturing = false
        captureBuffer.removeAll()
        captureStartTime = nil
    }
    
    // MARK: - Manual Event Trigger
    
    func triggerManualEvent() {
        guard !isInCaptureWindow else {
            print("⚠️ Already capturing an event")
            return
        }
        
        // Create synthetic trigger sample
        let now = Date()
        let trigger = IMUSample(
            timestamp: now,
            accelX: 0, accelY: 0, accelZ: 0,
            gyroX: 0, gyroY: 0, gyroZ: 0
        )
        
        startCapture(triggeredBy: trigger)
        print("👆 Manual event triggered")
    }
    
    // MARK: - Auto-Context Generation
    
    func generateAutoContext() -> EventContext {
        // Determine speed (prefer GPS, fallback to accelerometer)
        let speed: SpeedEstimate
        if locationService.isAuthorized && locationService.currentSpeed >= 0 {
            speed = locationService.speedEstimate
            print("🏃 Speed from GPS: \(speed.rawValue)")
        } else {
            speed = speedEstimator.estimatedSpeed
            print("🏃 Speed from IMU: \(speed.rawValue)")
        }
        
        // Get weather condition
        let weather = weatherService.currentWeather
        print("🌤️ Weather: \(weather.rawValue)")
        
        // Estimate road surface from vibration (simplified)
        let surface = estimateRoadSurface()
        print("🛣️ Road surface: \(surface.rawValue)")
        
        return EventContext(
            roadSurface: surface,
            weather: weather,
            speedEstimate: speed,
            notes: nil  // User can add notes manually
        )
    }
    
    private func estimateRoadSurface() -> RoadSurface {
        guard captureBuffer.count > 10 else { return .smooth }
        
        // Calculate vibration intensity from last captured event
        let magnitudes = captureBuffer.map { $0.accelMag }
        let avgMag = magnitudes.reduce(0, +) / Float(magnitudes.count)
        let variance = magnitudes.map { pow($0 - avgMag, 2) }.reduce(0, +) / Float(magnitudes.count)
        
        // Simple classification based on variance
        if variance > 0.5 {
            return .gravel
        } else if variance > 0.2 {
            return .cobbles
        } else if variance > 0.08 {
            return .rough
        } else {
            return .smooth
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        isInCaptureWindow = false
        isCapturing = false
        captureBuffer.removeAll()
        preBuffer.removeAll()
        detectedEvent = nil
        speedEstimator.reset()
    }
}
