//
//  WeatherService.swift
//  LumaHelmet
//
//  OpenMeteo API integration - iOS 17+
//

import Foundation
import CoreLocation
import Combine

// MARK: - Weather Models
struct WeatherResponse: Codable {
    let current: CurrentWeather
    
    struct CurrentWeather: Codable {
        let temperature_2m: Double
        let relative_humidity_2m: Int
        let precipitation: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let wind_direction_10m: Int
        let uv_index: Double?
    }
}

enum WeatherCondition: String {
    case clear = "Clear"
    case partlyCloudy = "Partly Cloudy"
    case cloudy = "Cloudy"
    case fog = "Fog"
    case drizzle = "Drizzle"
    case rain = "Rain"
    case heavyRain = "Heavy Rain"
    case snow = "Snow"
    case thunderstorm = "Thunderstorm"
    case unknown = "Unknown"
    
    var iconName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    static func from(code: Int) -> WeatherCondition {
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55: return .drizzle
        case 61, 63, 80, 81: return .rain
        case 65, 82: return .heavyRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }
}

struct ClothingRecommendation: Identifiable {
    let id = UUID()
    let item: String
    let reason: String
    let iconName: String
}

struct RoadWarning: Identifiable {
    let id = UUID()
    let warning: String
    let action: String
    let severity: Severity
    
    enum Severity: String {
        case low, medium, high
        
        var colorName: String {
            switch self {
            case .low: return "yellow"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }
}

// MARK: - Weather Service
class WeatherService: ObservableObject {
    @Published var currentWeather: WeatherResponse.CurrentWeather?
    @Published var weatherCondition: WeatherCondition = .unknown
    @Published var clothingRecommendations: [ClothingRecommendation] = []
    @Published var roadWarnings: [RoadWarning] = []
    @Published var isLoading = false
    @Published var lastUpdate: Date?
    @Published var errorMessage: String?
    
    private var cachedLocation: CLLocationCoordinate2D?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    
    func fetchWeather(for location: CLLocation) {
        let coord = location.coordinate
        
        // Check cache
        if let cached = cachedLocation,
           let timestamp = lastUpdate,
           Date().timeIntervalSince(timestamp) < cacheTimeout {
            let distance = sqrt(pow(cached.latitude - coord.latitude, 2) + pow(cached.longitude - coord.longitude, 2))
            if distance < 0.01 { return }
        }
        
        isLoading = true
        errorMessage = nil
        
        let urlString = "\(baseURL)?latitude=\(coord.latitude)&longitude=\(coord.longitude)&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m,uv_index&timezone=auto"
        
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
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self?.currentWeather = weather.current
                    self?.weatherCondition = WeatherCondition.from(code: weather.current.weather_code)
                    self?.generateRecommendations(from: weather.current)
                    self?.lastUpdate = Date()
                    self?.cachedLocation = coord
                } catch {
                    self?.errorMessage = "Failed to parse weather data"
                    print("Weather parse error: \(error)")
                }
            }
        }.resume()
    }
    
    private func generateRecommendations(from weather: WeatherResponse.CurrentWeather) {
        var clothing: [ClothingRecommendation] = []
        var warnings: [RoadWarning] = []
        
        let temp = weather.temperature_2m
        let precip = weather.precipitation
        let wind = weather.wind_speed_10m
        let uv = weather.uv_index ?? 0
        let code = weather.weather_code
        
        // Temperature clothing
        if temp < 5 {
            clothing.append(ClothingRecommendation(item: "Heavy thermal jacket", reason: "Temperature \(Int(temp))°C - Risk of hypothermia", iconName: "thermometer.snowflake"))
            clothing.append(ClothingRecommendation(item: "Winter gloves", reason: "Protect hands from cold", iconName: "hand.raised.fill"))
        } else if temp < 10 {
            clothing.append(ClothingRecommendation(item: "Thermal jersey", reason: "Temperature \(Int(temp))°C", iconName: "thermometer.medium"))
        } else if temp > 25 {
            clothing.append(ClothingRecommendation(item: "Light breathable jersey", reason: "Temperature \(Int(temp))°C - Stay cool", iconName: "thermometer.sun"))
        }
        
        // Precipitation
        if precip > 5 {
            clothing.append(ClothingRecommendation(item: "Waterproof rain jacket", reason: "Precipitation: \(precip)mm/h", iconName: "cloud.rain.fill"))
        } else if precip > 0.5 {
            clothing.append(ClothingRecommendation(item: "Light rain jacket", reason: "Light rain expected", iconName: "cloud.drizzle.fill"))
        }
        
        // UV
        if uv > 6 {
            clothing.append(ClothingRecommendation(item: "Sunscreen (SPF 30+)", reason: "UV index \(Int(uv)) - High", iconName: "sun.max.fill"))
            clothing.append(ClothingRecommendation(item: "UV sunglasses", reason: "Protect eyes", iconName: "eyeglasses"))
        } else if uv > 3 {
            clothing.append(ClothingRecommendation(item: "Sunscreen", reason: "Moderate UV", iconName: "sun.min.fill"))
        }
        
        // Wind
        if wind > 10 {
            clothing.append(ClothingRecommendation(item: "Windbreaker", reason: "Wind: \(Int(wind)) m/s", iconName: "wind"))
        }
        
        // Road warnings
        if precip > 0.5 || [51, 53, 55, 61, 63, 65, 80, 81, 82].contains(code) {
            warnings.append(RoadWarning(warning: "Slippery surface", action: "Increase braking distance, reduce speed", severity: precip > 5 ? .high : .medium))
        }
        
        if temp < 3 {
            warnings.append(RoadWarning(warning: "Ice risk", action: "Watch for black ice, especially on bridges", severity: .high))
        }
        
        if code == 45 || code == 48 {
            warnings.append(RoadWarning(warning: "Reduced visibility", action: "Use lights, reduce speed", severity: .high))
        }
        
        if wind > 15 {
            warnings.append(RoadWarning(warning: "Strong wind", action: "Be prepared for gusts", severity: wind > 20 ? .high : .medium))
        }
        
        if [95, 96, 99].contains(code) {
            warnings.append(RoadWarning(warning: "Thunderstorm", action: "Seek shelter immediately", severity: .high))
        }
        
        clothingRecommendations = clothing
        roadWarnings = warnings
    }
    
    var weatherState: String {
        guard let weather = currentWeather else { return "Dry" }
        if weather.precipitation > 0.5 { return "Wet" }
        if weather.temperature_2m < 3 { return "Icy" }
        return "Dry"
    }
}
