//
//  WeatherService.swift
//  SmartHelmetApp
//

import Foundation
import Combine
import CoreLocation
import SwiftUI

class WeatherService: NSObject, ObservableObject {
    @Published var currentWeather: WeatherData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var clothingRecommendations: [ClothingRecommendation] = []
    
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    func fetchWeather(for location: CLLocation) {
        isLoading = true
        errorMessage = nil
        
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        // Open-Meteo API - free, no key required!
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,uv_index&hourly=temperature_2m,weather_code,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&timezone=auto&forecast_days=7"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.loadMockData()
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    self?.loadMockData()
                    return
                }
                
                self?.parseOpenMeteoData(data, location: location)
            }
        }.resume()
    }
    
    private func parseOpenMeteoData(_ data: Data, location: CLLocation) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let hourly = json["hourly"] as? [String: Any],
                  let daily = json["daily"] as? [String: Any] else {
                loadMockData()
                return
            }
            
            // Parse current weather
            let temperature = current["temperature_2m"] as? Double ?? 20
            let humidity = current["relative_humidity_2m"] as? Int ?? 50
            let feelsLike = current["apparent_temperature"] as? Double ?? temperature
            let weatherCode = current["weather_code"] as? Int ?? 0
            let windSpeed = current["wind_speed_10m"] as? Double ?? 0
            let windDirection = current["wind_direction_10m"] as? Double ?? 0
            let uvIndex = current["uv_index"] as? Double ?? 0
            
            // Parse hourly forecast
            let hourlyTemps = hourly["temperature_2m"] as? [Double] ?? []
            let hourlyCodes = hourly["weather_code"] as? [Int] ?? []
            let hourlyPrecip = hourly["precipitation_probability"] as? [Int] ?? []
            
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "ha"
            
            var hourlyForecast: [HourlyForecast] = []
            for i in 0..<min(8, hourlyTemps.count) {
                let hour = i == 0 ? "Now" : hourFormatter.string(from: Date().addingTimeInterval(Double(i) * 3600))
                hourlyForecast.append(HourlyForecast(
                    hour: hour,
                    temperature: hourlyTemps[i],
                    condition: mapWeatherCode(hourlyCodes.count > i ? hourlyCodes[i] : 0),
                    precipitation: hourlyPrecip.count > i ? hourlyPrecip[i] : 0
                ))
            }
            
            // Parse daily forecast
            let dailyMaxTemps = daily["temperature_2m_max"] as? [Double] ?? []
            let dailyMinTemps = daily["temperature_2m_min"] as? [Double] ?? []
            let dailyCodes = daily["weather_code"] as? [Int] ?? []
            let dailyPrecip = daily["precipitation_probability_max"] as? [Int] ?? []
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            
            var dailyForecast: [DailyForecast] = []
            for i in 0..<min(7, dailyMaxTemps.count) {
                let day = i == 0 ? "Today" : dayFormatter.string(from: Date().addingTimeInterval(Double(i) * 86400))
                dailyForecast.append(DailyForecast(
                    day: day,
                    high: dailyMaxTemps[i],
                    low: dailyMinTemps.count > i ? dailyMinTemps[i] : dailyMaxTemps[i] - 8,
                    condition: mapWeatherCode(dailyCodes.count > i ? dailyCodes[i] : 0),
                    precipitation: dailyPrecip.count > i ? dailyPrecip[i] : 0
                ))
            }
            
            // Get location name
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                let locationName = placemarks?.first?.locality ?? "Current Location"
                
                DispatchQueue.main.async {
                    self?.currentWeather = WeatherData(
                        temperature: temperature,
                        feelsLike: feelsLike,
                        condition: self?.mapWeatherCode(weatherCode) ?? .partlyCloudy,
                        humidity: humidity,
                        windSpeed: windSpeed,
                        windDirection: self?.windDirectionString(windDirection) ?? "N",
                        uvIndex: Int(uvIndex),
                        precipitation: hourlyPrecip.first ?? 0,
                        location: locationName,
                        hourlyForecast: hourlyForecast,
                        dailyForecast: dailyForecast
                    )
                    
                    self?.generateClothingRecommendations()
                }
            }
            
        } catch {
            errorMessage = "Failed to parse weather data"
            loadMockData()
        }
    }
    
    private func mapWeatherCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1:
            return .sunny
        case 2:
            return .partlyCloudy
        case 3:
            return .cloudy
        case 45, 48:
            return .foggy
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return .rainy
        case 71, 73, 75, 77, 85, 86:
            return .snowy
        case 95, 96, 99:
            return .stormy
        default:
            return .partlyCloudy
        }
    }
    
    private func windDirectionString(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    func loadMockData() {
        isLoading = false
        
        // Generate mock hourly forecast
        let hours = ["Now", "1PM", "2PM", "3PM", "4PM", "5PM", "6PM", "7PM"]
        let hourlyForecast = hours.enumerated().map { index, hour in
            HourlyForecast(
                hour: hour,
                temperature: Double.random(in: 18...24),
                condition: [.sunny, .partlyCloudy, .cloudy][index % 3],
                precipitation: index > 4 ? Int.random(in: 10...40) : 0
            )
        }
        
        // Generate mock daily forecast
        let days = ["Today", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dailyForecast = days.enumerated().map { index, day in
            DailyForecast(
                day: day,
                high: Double.random(in: 20...28),
                low: Double.random(in: 12...18),
                condition: WeatherCondition.allCases.randomElement() ?? .sunny,
                precipitation: Int.random(in: 0...60)
            )
        }
        
        currentWeather = WeatherData(
            temperature: 22,
            feelsLike: 24,
            condition: .partlyCloudy,
            humidity: 65,
            windSpeed: 12,
            windDirection: "NW",
            uvIndex: 6,
            precipitation: 20,
            location: "London",
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast
        )
        
        generateClothingRecommendations()
    }
    
    func generateClothingRecommendations() {
        guard let weather = currentWeather else { return }
        
        var recommendations: [ClothingRecommendation] = []
        
        // Always recommend helmet (obviously!)
        recommendations.append(ClothingRecommendation(
            item: "Smart Helmet",
            icon: "helmet",
            reason: "Safety first! Your smart helmet is connected.",
            priority: .essential
        ))
        
        // Temperature-based recommendations
        if weather.temperature < 10 {
            recommendations.append(ClothingRecommendation(
                item: "Thermal Jersey",
                icon: "tshirt.fill",
                reason: "It's cold! Layer up with thermal wear.",
                priority: .essential
            ))
            recommendations.append(ClothingRecommendation(
                item: "Winter Gloves",
                icon: "hand.raised.fill",
                reason: "Keep your hands warm for safe braking.",
                priority: .essential
            ))
            recommendations.append(ClothingRecommendation(
                item: "Leg Warmers",
                icon: "figure.walk",
                reason: "Protect your legs from the cold.",
                priority: .recommended
            ))
        } else if weather.temperature < 18 {
            recommendations.append(ClothingRecommendation(
                item: "Light Jacket",
                icon: "jacket.fill",
                reason: "Cool weather - a light layer helps.",
                priority: .recommended
            ))
            recommendations.append(ClothingRecommendation(
                item: "Arm Warmers",
                icon: "figure.arms.open",
                reason: "Easy to remove if you warm up.",
                priority: .optional
            ))
        } else if weather.temperature > 25 {
            recommendations.append(ClothingRecommendation(
                item: "Breathable Jersey",
                icon: "tshirt.fill",
                reason: "Hot day! Wear moisture-wicking fabric.",
                priority: .essential
            ))
            recommendations.append(ClothingRecommendation(
                item: "Sunscreen",
                icon: "sun.max.fill",
                reason: "UV Index is \(weather.uvIndex). Protect your skin!",
                priority: .essential
            ))
        } else {
            recommendations.append(ClothingRecommendation(
                item: "Cycling Jersey",
                icon: "tshirt.fill",
                reason: "Perfect cycling weather!",
                priority: .recommended
            ))
        }
        
        // Weather condition-based recommendations
        switch weather.condition {
        case .rainy, .stormy:
            recommendations.append(ClothingRecommendation(
                item: "Rain Jacket",
                icon: "cloud.rain.fill",
                reason: "Rain expected! Stay dry.",
                priority: .essential
            ))
            recommendations.append(ClothingRecommendation(
                item: "Waterproof Overshoes",
                icon: "shoe.fill",
                reason: "Keep your feet dry.",
                priority: .recommended
            ))
            recommendations.append(ClothingRecommendation(
                item: "Clear Glasses",
                icon: "eyeglasses",
                reason: "Protect your eyes from rain spray.",
                priority: .recommended
            ))
        case .sunny:
            recommendations.append(ClothingRecommendation(
                item: "Sunglasses",
                icon: "sunglasses.fill",
                reason: "Bright conditions - protect your eyes.",
                priority: .essential
            ))
        case .windy:
            recommendations.append(ClothingRecommendation(
                item: "Wind Vest",
                icon: "wind",
                reason: "Windy! A vest blocks the chill.",
                priority: .recommended
            ))
        case .foggy:
            recommendations.append(ClothingRecommendation(
                item: "High-Vis Vest",
                icon: "exclamationmark.triangle.fill",
                reason: "Low visibility - be seen!",
                priority: .essential
            ))
        default:
            break
        }
        
        // Wind-based recommendations
        if weather.windSpeed > 20 {
            recommendations.append(ClothingRecommendation(
                item: "Aero Helmet Cover",
                icon: "wind",
                reason: "Strong winds - reduce drag.",
                priority: .optional
            ))
        }
        
        clothingRecommendations = recommendations
    }
}

// MARK: - Location Manager Delegate
extension WeatherService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        currentLocation = location
        fetchWeather(for: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
        // Load mock data as fallback
        loadMockData()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied"
            loadMockData()
        default:
            break
        }
    }
}
