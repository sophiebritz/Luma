//
//  EventClassificationSheet.swift
//  NavHalo Pilot
//
//  Modal sheet for classifying detected events with AUTO-POPULATED context
//

import SwiftUI

struct EventClassificationSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let event: EventWindow
    let onSave: (EventLabel, EventContext) -> Void
    
    // Auto-populated from services (passed as defaults)
    let autoDetectedContext: EventContext
    
    @State private var selectedLabel: EventLabel?
    @State private var roadSurface: RoadSurface
    @State private var weather: WeatherCondition
    @State private var speedEstimate: SpeedEstimate
    @State private var notes: String = ""
    
    @State private var showAutoDetectBadge = true
    
    init(event: EventWindow,
         autoDetectedContext: EventContext,
         onSave: @escaping (EventLabel, EventContext) -> Void) {
        self.event = event
        self.autoDetectedContext = autoDetectedContext
        self.onSave = onSave
        
        // Initialize state with auto-detected values
        _roadSurface = State(initialValue: autoDetectedContext.roadSurface)
        _weather = State(initialValue: autoDetectedContext.weather)
        _speedEstimate = State(initialValue: autoDetectedContext.speedEstimate)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Event Info Header
                    eventInfoCard
                    
                    // Auto-detection Banner
                    if showAutoDetectBadge {
                        autoDetectBanner
                    }
                    
                    // Primary Classification
                    classificationButtons
                    
                    // Context Inputs (Auto-populated)
                    contextSection
                    
                    // Notes
                    notesSection
                    
                    // Save Button
                    saveButton
                }
                .padding()
            }
            .navigationTitle("Classify Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Event Info Card
    
    private var eventInfoCard: some View {
        VStack(spacing: 12) {
            Text("What just happened?")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack {
                    Text(String(format: "%.2fg", event.peakAccelMag))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(event.peakAccelMag > 4.0 ? .red : .orange)
                    Text("Peak G-Force")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(String(format: "%.1f", event.peakJerk))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                    Text("Peak Jerk")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(String(format: "%.1fs", event.duration))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Auto-Detection Banner
    
    private var autoDetectBanner: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Detected Context")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                HStack(spacing: 12) {
                    Label(speedEstimate.rawValue, systemImage: "speedometer")
                        .font(.caption2)
                    Label(weather.rawValue, systemImage: weather.icon)
                        .font(.caption2)
                    Label(roadSurface.rawValue, systemImage: "road.lanes")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showAutoDetectBadge = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Classification Buttons
    
    private var classificationButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Type")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(EventLabel.allCases, id: \.self) { label in
                    Button(action: {
                        selectedLabel = label
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: label.icon)
                                .font(.title2)
                            
                            Text(label.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(
                            selectedLabel == label
                                ? label.color.opacity(0.2)
                                : Color(.systemGray6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedLabel == label ? label.color : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Context Section
    
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Context (Auto-Detected)")
                .font(.headline)
            
            // Road Surface
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Road Surface", systemImage: "road.lanes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if roadSurface == autoDetectedContext.roadSurface {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Picker("Road Surface", selection: $roadSurface) {
                    ForEach(RoadSurface.allCases, id: \.self) { surface in
                        Text(surface.rawValue).tag(surface)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Weather
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Weather", systemImage: "cloud.sun")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if weather == autoDetectedContext.weather {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Picker("Weather", selection: $weather) {
                    ForEach(WeatherCondition.allCases, id: \.self) { condition in
                        Text(condition.rawValue).tag(condition)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Speed Estimate
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Speed", systemImage: "speedometer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if speedEstimate == autoDetectedContext.speedEstimate {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Picker("Speed", selection: $speedEstimate) {
                    ForEach(SpeedEstimate.allCases, id: \.self) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes (Optional)", systemImage: "note.text")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextEditor(text: $notes)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: saveClassification) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Classification")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selectedLabel?.color ?? Color.gray)
            .cornerRadius(12)
        }
        .disabled(selectedLabel == nil)
        .opacity(selectedLabel == nil ? 0.5 : 1.0)
    }
    
    // MARK: - Actions
    
    private func saveClassification() {
        guard let label = selectedLabel else { return }
        
        let context = EventContext(
            roadSurface: roadSurface,
            weather: weather,
            speedEstimate: speedEstimate,
            notes: notes.isEmpty ? nil : notes
        )
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave(label, context)
        dismiss()
    }
}
