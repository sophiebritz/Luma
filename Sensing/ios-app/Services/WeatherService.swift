//
//  WeatherService.swift
//  NavHalo Pilot
//
//  Auto-detect weather conditions using OpenMeteo API (free, no API key)
//

import Foundation
import CoreLocation
import Combine

class WeatherService: ObservableObject {
    @Published var currentWeather: WeatherCondition = .dry
    @Published var temperature: Double = 0.0  // Celsius
    @Published var precipitation: Double = 0.0  // mm
    @Published var isLoading: Bool = false
    @Published var lastUpdate: Date?
    
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 300  // 5 minutes
    private var lastLocation: CLLocation?
    
    // MARK: - Public Methods
    
    func fetchWeather(for location: CLLocation) {
        // Avoid excessive API calls (5 min throttle)
        if let lastUpdate = lastUpdate,
           Date().timeIntervalSince(lastUpdate) < updateInterval,
           let lastLoc = lastLocation,
           location.distance(from: lastLoc) < 1000 {  // < 1km movement
            print("🌤️ Using cached weather data")
            return
        }
        
        isLoading = true
        lastLocation = location
        
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        // OpenMeteo API endpoint (free, no API key required)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,precipitation,weather_code&timezone=auto"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid weather API URL")
            isLoading = false
            return
        }
        
        print("🌤️ Fetching weather for: \(lat), \(lon)")
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: WeatherResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    print("❌ Weather fetch error: \(error)")
                }
            } receiveValue: { [weak self] response in
                self?.processWeatherResponse(response)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private Methods
    
    private func processWeatherResponse(_ response: WeatherResponse) {
        temperature = response.current.temperature_2m
        precipitation = response.current.precipitation
        
        // Determine weather condition
        let weatherCode = response.current.weather_code
        
        if precipitation > 0.5 {
            // Active precipitation
            if temperature < 2.0 {
                currentWeather = .icy
            } else {
                currentWeather = .wet
            }
        } else {
            // No precipitation
            // Check for recent rain (road might still be wet)
            if weatherCode >= 51 && weatherCode <= 67 {
                // Rain/drizzle codes - road likely wet
                currentWeather = .wet
            } else if weatherCode >= 71 && weatherCode <= 77 {
                // Snow codes
                currentWeather = .icy
            } else if temperature < 0 {
                // Below freezing - possible ice
                currentWeather = .icy
            } else {
                currentWeather = .dry
            }
        }
        
        lastUpdate = Date()
        
        print("🌤️ Weather updated:")
        print("   • Condition: \(currentWeather.rawValue)")
        print("   • Temperature: \(String(format: "%.1f", temperature))°C")
        print("   • Precipitation: \(String(format: "%.1f", precipitation))mm")
    }
}

// MARK: - Weather Response Models

struct WeatherResponse: Codable {
    let current: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature_2m: Double
    let precipitation: Double
    let weather_code: Int
}

// MARK: - Weather Condition Extension

extension WeatherCondition {
    var icon: String {
        switch self {
        case .dry: return "sun.max.fill"
        case .wet: return "cloud.rain.fill"
        case .icy: return "snowflake"
        }
    }
    
    var description: String {
        switch self {
        case .dry: return "Dry roads"
        case .wet: return "Wet roads"
        case .icy: return "Icy conditions"
        }
    }
}
