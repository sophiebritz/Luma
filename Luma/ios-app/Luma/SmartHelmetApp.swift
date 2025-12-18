//
//  SmartHelmetApp.swift
//  SmartHelmetApp
//
//  Smart Bike Helmet iOS App
//  - Weather & clothing recommendations for cycling
//  - BLE helmet control (turn signals, crash detection)
//  - Navigation with auto-indication
//

import SwiftUI

@main
struct SmartHelmetApp: App {
    @StateObject private var weatherService = WeatherService()
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var navigationService = NavigationService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(weatherService)
                .environmentObject(bluetoothManager)
                .environmentObject(navigationService)
        }
    }
}
