//
//  DataCollectionService.swift
//  NavHalo Pilot
//
//  Manages data collection sessions and InfluxDB uploads
//

import Foundation
import Combine

class DataCollectionService: ObservableObject {
    
    // MARK: - InfluxDB Configuration
    
    // ⚠️ UPDATE THESE WITH YOUR INFLUXDB CREDENTIALS
    private let influxURL = "https://YOUR-INFLUX-URL.influxdata.com"
    private let influxToken = "YOUR_API_TOKEN_HERE"
    private let influxOrg = "YOUR_ORG_HERE"
    private let influxBucket = "navhalo-pilot"
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var sessionDuration: TimeInterval = 0
    @Published var uploadStatus: String = ""
    
    @Published var brakeCount = 0
    @Published var crashCount = 0
    @Published var bumpCount = 0
    @Published var turnCount = 0
    @Published var normalCount = 0
    
    // MARK: - Private Properties
    
    private var sessionID: String?
    private var sessionStartTime: Date?
    private var sessionTimer: Timer?
    
    // MARK: - Session Management
    
    func startSession() {
        sessionID = UUID().uuidString
        sessionStartTime = Date()
        isRecording = true
        
        // Reset counters
        brakeCount = 0
        crashCount = 0
        bumpCount = 0
        turnCount = 0
        normalCount = 0
        
        // Start duration timer
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.sessionStartTime else { return }
            self.sessionDuration = Date().timeIntervalSince(startTime)
        }
        
        print("🔴 Session started: \(sessionID!)")
    }
    
    func stopSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        isRecording = false
        
        let totalEvents = brakeCount + crashCount + bumpCount + turnCount + normalCount
        print("⏹️ Session stopped. Total events: \(totalEvents)")
    }
    
    // MARK: - Event Saving
    
    func saveClassifiedEvent(_ eventWindow: EventWindow,
                            label: EventLabel,
                            context: EventContext) {
        
        guard let sessionID = sessionID else {
            print("⚠️ No active session")
            return
        }
        
        // Update counters
        DispatchQueue.main.async {
            switch label {
            case .brake: self.brakeCount += 1
            case .crash: self.crashCount += 1
            case .bump: self.bumpCount += 1
            case .turn: self.turnCount += 1
            case .normal: self.normalCount += 1
            case .unknown: break
            }
        }
        
        // Upload to InfluxDB
        uploadEventWindow(eventWindow, sessionID: sessionID, label: label, context: context)
    }
    
    // MARK: - InfluxDB Upload
    
    private func uploadEventWindow(_ eventWindow: EventWindow,
                                   sessionID: String,
                                   label: EventLabel,
                                   context: EventContext) {
        
        var lineProtocol = ""
        
        // Write individual IMU samples
        for (index, sample) in eventWindow.samples.enumerated() {
            let timestamp = Int64(sample.timestamp.timeIntervalSince1970 * 1_000_000_000)
            
            let line = """
            labeled_events,\
            session_id=\(sessionID),\
            event_id=\(eventWindow.id.uuidString),\
            label=\(label.rawValue),\
            road_surface=\(context.roadSurface.rawValue),\
            weather=\(context.weather.rawValue),\
            speed=\(context.speedEstimate.rawValue.replacingOccurrences(of: " ", with: "_")),\
            sample_index=\(index) \
            accel_x=\(sample.accelX),\
            accel_y=\(sample.accelY),\
            accel_z=\(sample.accelZ),\
            gyro_x=\(sample.gyroX),\
            gyro_y=\(sample.gyroY),\
            gyro_z=\(sample.gyroZ),\
            accel_mag=\(sample.accelMag) \
            \(timestamp)
            """
            
            lineProtocol += line + "\n"
        }
        
        // Write event metadata
        let metadataTimestamp = Int64(eventWindow.timestamp.timeIntervalSince1970 * 1_000_000_000)
        let metadataLine = """
        event_metadata,\
        session_id=\(sessionID),\
        event_id=\(eventWindow.id.uuidString),\
        label=\(label.rawValue) \
        peak_accel=\(eventWindow.peakAccelMag),\
        peak_jerk=\(eventWindow.peakJerk),\
        sample_count=\(eventWindow.samples.count)i,\
        duration=\(eventWindow.duration) \
        \(metadataTimestamp)
        """
        
        lineProtocol += metadataLine + "\n"
        
        // Write notes if present
        if let notes = context.notes, !notes.isEmpty {
            let escapedNotes = notes.replacingOccurrences(of: "\"", with: "\\\"")
            let notesLine = """
            event_notes,\
            session_id=\(sessionID),\
            event_id=\(eventWindow.id.uuidString) \
            notes="\(escapedNotes)" \
            \(metadataTimestamp)
            """
            lineProtocol += notesLine + "\n"
        }
        
        // Send to InfluxDB
        sendToInfluxDB(lineProtocol)
    }
    
    private func sendToInfluxDB(_ lineProtocol: String) {
        let urlString = "\(influxURL)/api/v2/write?org=\(influxOrg)&bucket=\(influxBucket)&precision=ns"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid InfluxDB URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(influxToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = lineProtocol.data(using: .utf8)
        
        DispatchQueue.main.async {
            self.uploadStatus = "⏳ Uploading..."
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    self.uploadStatus = "❌ Error: \(error.localizedDescription)"
                    print("❌ Upload error: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 204:
                        self.uploadStatus = "✅ Uploaded"
                        print("✅ Event uploaded successfully")
                        
                        // Clear status after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.uploadStatus = ""
                        }
                        
                    case 401:
                        self.uploadStatus = "❌ Auth failed"
                        print("❌ InfluxDB authentication failed - check token")
                        
                    case 404:
                        self.uploadStatus = "❌ Bucket not found"
                        print("❌ Bucket '\(self.influxBucket)' not found")
                        
                    default:
                        self.uploadStatus = "⚠️ HTTP \(httpResponse.statusCode)"
                        print("⚠️ HTTP \(httpResponse.statusCode)")
                        
                        if let data = data, let body = String(data: data, encoding: .utf8) {
                            print("Response: \(body)")
                        }
                    }
                }
            }
        }.resume()
    }
}
