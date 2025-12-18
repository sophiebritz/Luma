//
//  WeatherView.swift
//  LumaHelmet
//
//  Weather display with cycling recommendations - iOS 17+
//

import SwiftUI

struct WeatherView: View {
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var locationService: LocationService
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Current weather card
                    CurrentWeatherCard()
                    
                    // Road warnings
                    if !weatherService.roadWarnings.isEmpty {
                        RoadWarningsCard()
                    }
                    
                    // Clothing recommendations
                    if !weatherService.clothingRecommendations.isEmpty {
                        ClothingCard()
                    }
                    
                    // Empty state
                    if weatherService.currentWeather == nil && !weatherService.isLoading {
                        EmptyWeatherView()
                    }
                }
                .padding()
            }
            .navigationTitle("Weather")
            .refreshable {
                await refreshWeather()
            }
            .onAppear {
                if let location = locationService.currentLocation {
                    weatherService.fetchWeather(for: location)
                }
            }
        }
    }
    
    private func refreshWeather() async {
        if let location = locationService.currentLocation {
            weatherService.fetchWeather(for: location)
            // Small delay for visual feedback
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

// MARK: - Current Weather Card
struct CurrentWeatherCard: View {
    @EnvironmentObject var weatherService: WeatherService
    
    var body: some View {
        VStack(spacing: 16) {
            if weatherService.isLoading {
                ProgressView()
                    .padding(40)
            } else if let weather = weatherService.currentWeather {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(weather.temperature_2m))°")
                            .font(.system(size: 64, weight: .thin))
                        
                        Text(weatherService.weatherCondition.rawValue)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: weatherService.weatherCondition.iconName)
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Divider()
                
                // Weather details grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WeatherDetailItem(icon: "wind", value: "\(Int(weather.wind_speed_10m))", unit: "m/s", label: "Wind")
                    WeatherDetailItem(icon: "humidity", value: "\(weather.relative_humidity_2m)", unit: "%", label: "Humidity")
                    WeatherDetailItem(icon: "drop.fill", value: String(format: "%.1f", weather.precipitation), unit: "mm", label: "Precip")
                    
                    if let uv = weather.uv_index {
                        WeatherDetailItem(icon: "sun.max.fill", value: "\(Int(uv))", unit: "", label: "UV Index")
                    }
                }
                
                if let lastUpdate = weatherService.lastUpdate {
                    Text("Updated \(lastUpdate, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WeatherDetailItem: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.title3)
            
            HStack(spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Road Warnings Card
struct RoadWarningsCard: View {
    @EnvironmentObject var weatherService: WeatherService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Road Conditions", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            
            ForEach(weatherService.roadWarnings) { warning in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color(warning.severity.colorName))
                            .frame(width: 8, height: 8)
                        
                        Text(warning.warning)
                            .font(.subheadline.bold())
                    }
                    
                    Text(warning.action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Clothing Card
struct ClothingCard: View {
    @EnvironmentObject var weatherService: WeatherService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What to Wear", systemImage: "tshirt.fill")
                .font(.headline)
                .foregroundStyle(.purple)
            
            ForEach(weatherService.clothingRecommendations) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.iconName)
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.item)
                            .font(.subheadline.bold())
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Empty Weather View
struct EmptyWeatherView: View {
    @EnvironmentObject var weatherService: WeatherService
    @EnvironmentObject var locationService: LocationService
    
    var body: some View {
        ContentUnavailableView {
            Label("No Weather Data", systemImage: "location.slash")
        } description: {
            Text("Enable location services to get weather information")
        } actions: {
            Button("Refresh") {
                if let location = locationService.currentLocation {
                    weatherService.fetchWeather(for: location)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
