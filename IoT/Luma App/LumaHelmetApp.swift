//
//  LumaHelmetApp.swift
//  LumaHelmet
//
//  Smart Cycling Helmet iOS App - iOS 17+
//  Features: BLE communication, Navigation, Weather, Safety Analytics
//

import SwiftUI
import Combine

@main
struct LumaHelmetApp: App {
    // Use StateObject for managers that need to persist across the app lifecycle
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.bleManager)
                .environmentObject(appState.locationService)
                .environmentObject(appState.weatherService)
                .environmentObject(appState.rideService)
                .environmentObject(appState.navigationService)
        }
    }
}

/// Central app state manager to coordinate between services
class AppState: ObservableObject {
    let bleManager = BLEManager()
    let locationService = LocationService()
    let weatherService = WeatherService()
    let rideService: RideService
    let navigationService = NavigationService()
    
    init() {
        // Initialize ride service with location service reference
        self.rideService = RideService(locationService: locationService)
        
        // Set up event handling from BLE to ride service
        bleManager.onEventDetected = { [weak self] event in
            self?.rideService.recordEvent(event)
        }
        
        // Connect location updates to ride service
        locationService.onLocationUpdate = { [weak self] location in
            self?.rideService.updateLocation(location)
            
            // Also update weather periodically
            if let lastWeather = self?.weatherService.lastUpdate,
               Date().timeIntervalSince(lastWeather) > 300 {
                self?.weatherService.fetchWeather(for: location)
            } else if self?.weatherService.lastUpdate == nil {
                self?.weatherService.fetchWeather(for: location)
            }
        }
    }
}
