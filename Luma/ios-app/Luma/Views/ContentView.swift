//
//  ContentView.swift
//  SmartHelmetApp
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var navigationService: NavigationService
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WeatherView()
                .tabItem {
                    Image(systemName: "sun.max.fill")
                    Text("Weather")
                }
                .tag(0)
            
            NavigationMapView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Navigate")
                }
                .tag(1)
            
            HelmetControlView()
                .tabItem {
                    Image(systemName: "bicycle")
                    Text("Helmet")
                }
                .tag(2)
            
            RideHistoryView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Rides")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(4)
        }
        .tint(.orange)
    }
}

#Preview {
    ContentView()
        .environmentObject(WeatherService())
        .environmentObject(BluetoothManager())
        .environmentObject(NavigationService())
}
