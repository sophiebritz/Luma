//
//  WeatherModels.swift
//  SmartHelmetApp
//

import Foundation
import SwiftUI

// MARK: - Weather Condition
enum WeatherCondition: String, CaseIterable {
    case sunny = "sunny"
    case partlyCloudy = "partly_cloudy"
    case cloudy = "cloudy"
    case rainy = "rainy"
    case stormy = "stormy"
    case snowy = "snowy"
    case foggy = "foggy"
    case windy = "windy"
    
    var icon: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rainy: return "cloud.rain.fill"
        case .stormy: return "cloud.bolt.rain.fill"
        case .snowy: return "cloud.snow.fill"
        case .foggy: return "cloud.fog.fill"
        case .windy: return "wind"
        }
    }
    
    var color: Color {
        switch self {
        case .sunny: return .yellow
        case .partlyCloudy: return .orange
        case .cloudy: return .gray
        case .rainy: return .blue
        case .stormy: return .purple
        case .snowy: return .cyan
        case .foggy: return .gray.opacity(0.7)
        case .windy: return .teal
        }
    }
    
    var backgroundGradient: [Color] {
        switch self {
        case .sunny: 
            return [Color(hex: "FF9500"), Color(hex: "FF5E3A"), Color(hex: "FF2D55")]
        case .partlyCloudy: 
            return [Color(hex: "5AC8FA"), Color(hex: "007AFF"), Color(hex: "5856D6")]
        case .cloudy: 
            return [Color(hex: "8E8E93"), Color(hex: "636366"), Color(hex: "48484A")]
        case .rainy: 
            return [Color(hex: "007AFF"), Color(hex: "5856D6"), Color(hex: "AF52DE")]
        case .stormy: 
            return [Color(hex: "5856D6"), Color(hex: "AF52DE"), Color(hex: "1C1C1E")]
        case .snowy: 
            return [Color(hex: "B4D4E7"), Color(hex: "8BB8D0"), Color(hex: "5AC8FA")]
        case .foggy: 
            return [Color(hex: "C7C7CC"), Color(hex: "8E8E93"), Color(hex: "636366")]
        case .windy: 
            return [Color(hex: "64D2FF"), Color(hex: "5AC8FA"), Color(hex: "007AFF")]
        }
    }
}

// MARK: - Weather Data
struct WeatherData: Identifiable {
    let id = UUID()
    var temperature: Double
    var feelsLike: Double
    var condition: WeatherCondition
    var humidity: Int
    var windSpeed: Double
    var windDirection: String
    var uvIndex: Int
    var precipitation: Int
    var location: String
    var hourlyForecast: [HourlyForecast]
    var dailyForecast: [DailyForecast]
    
    var temperatureString: String {
        "\(Int(temperature))Â°"
    }
    
    var feelsLikeString: String {
        "Feels like \(Int(feelsLike))Â°"
    }
}

struct HourlyForecast: Identifiable {
    let id = UUID()
    var hour: String
    var temperature: Double
    var condition: WeatherCondition
    var precipitation: Int
}

struct DailyForecast: Identifiable {
    let id = UUID()
    var day: String
    var high: Double
    var low: Double
    var condition: WeatherCondition
    var precipitation: Int
}

// MARK: - Cycling Clothing Recommendation
struct ClothingRecommendation: Identifiable {
    let id = UUID()
    var item: String
    var icon: String
    var reason: String
    var priority: ClothingPriority
}

enum ClothingPriority {
    case essential
    case recommended
    case optional
    
    var color: Color {
        switch self {
        case .essential: return .red
        case .recommended: return .orange
        case .optional: return .green
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
