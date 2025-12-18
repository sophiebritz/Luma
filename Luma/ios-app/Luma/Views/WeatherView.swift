//
//  WeatherView.swift
//  SmartHelmetApp
//
//  WeatherFit-style weather display with cycling clothing recommendations
//

import SwiftUI

struct WeatherView: View {
    @EnvironmentObject var weatherService: WeatherService
    @State private var showClothingDetail = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic background gradient
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Main weather display with cyclist
                        mainWeatherSection(geometry: geometry)
                        
                        // Clothing recommendations
                        clothingSection
                        
                        // Hourly forecast
                        hourlyForecastSection
                        
                        // Daily forecast
                        dailyForecastSection
                        
                        // Weather details grid
                        weatherDetailsGrid
                        
                        Spacer(minLength: 100)
                    }
                }
                .refreshable {
                    weatherService.requestLocation()
                }
            }
        }
        .onAppear {
            weatherService.requestLocation()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: weatherService.currentWeather?.condition.backgroundGradient ?? [.blue, .purple]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 1.0), value: weatherService.currentWeather?.condition)
    }
    
    // MARK: - Main Weather Section
    
    private func mainWeatherSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            // Location
            HStack {
                Image(systemName: "location.fill")
                    .font(.caption)
                Text(weatherService.currentWeather?.location ?? "Loading...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 60)
            
            // Cyclist Avatar
            CyclistAvatarView(
                weather: weatherService.currentWeather,
                recommendations: weatherService.clothingRecommendations
            )
            .frame(height: geometry.size.height * 0.35)
            
            // Temperature
            VStack(spacing: 4) {
                Text(weatherService.currentWeather?.temperatureString ?? "--Â°")
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                
                Text(weatherService.currentWeather?.feelsLikeString ?? "")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 8) {
                    Image(systemName: weatherService.currentWeather?.condition.icon ?? "questionmark")
                        .font(.title2)
                    Text(weatherService.currentWeather?.condition.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "Loading")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Clothing Section
    
    private var clothingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "tshirt.fill")
                    .foregroundColor(.orange)
                Text("What to Wear")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button(action: { showClothingDetail.toggle() }) {
                    Text("See All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(weatherService.clothingRecommendations.prefix(5)) { item in
                        ClothingItemCard(item: item)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 32)
    }
    
    // MARK: - Hourly Forecast
    
    private var hourlyForecastSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.cyan)
                Text("Hourly Forecast")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(weatherService.currentWeather?.hourlyForecast ?? []) { hour in
                        HourlyForecastCard(forecast: hour)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 32)
    }
    
    // MARK: - Daily Forecast
    
    private var dailyForecastSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.green)
                Text("7-Day Forecast")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(weatherService.currentWeather?.dailyForecast ?? []) { day in
                    DailyForecastRow(forecast: day)
                    if day.id != weatherService.currentWeather?.dailyForecast.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.2))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .padding(.horizontal, 20)
        }
        .padding(.top, 32)
    }
    
    // MARK: - Weather Details Grid
    
    private var weatherDetailsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.yellow)
                Text("Details")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                WeatherDetailCard(
                    icon: "humidity.fill",
                    title: "Humidity",
                    value: "\(weatherService.currentWeather?.humidity ?? 0)%",
                    color: .blue
                )
                
                WeatherDetailCard(
                    icon: "wind",
                    title: "Wind",
                    value: "\(Int(weatherService.currentWeather?.windSpeed ?? 0)) km/h",
                    color: .teal
                )
                
                WeatherDetailCard(
                    icon: "sun.max.fill",
                    title: "UV Index",
                    value: "\(weatherService.currentWeather?.uvIndex ?? 0)",
                    color: .orange
                )
                
                WeatherDetailCard(
                    icon: "drop.fill",
                    title: "Precipitation",
                    value: "\(weatherService.currentWeather?.precipitation ?? 0)%",
                    color: .cyan
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 32)
    }
}

// MARK: - Cyclist Avatar View

struct CyclistAvatarView: View {
    let weather: WeatherData?
    let recommendations: [ClothingRecommendation]
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background scene
            sceneBackground
            
            // Cyclist
            VStack(spacing: 0) {
                // Helmet
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FF6B00"), Color(hex: "FF9500")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 60, height: 40)
                    
                    // LED strip on helmet
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 40, height: 4)
                        .offset(y: 12)
                        .opacity(isAnimating ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isAnimating)
                }
                
                // Head
                Circle()
                    .fill(Color(hex: "FFD5A5"))
                    .frame(width: 40, height: 40)
                    .overlay(
                        // Sunglasses if sunny
                        Group {
                            if weather?.condition == .sunny || weather?.uvIndex ?? 0 > 5 {
                                sunglasses
                            }
                        }
                    )
                    .offset(y: -5)
                
                // Body/Jersey
                ZStack {
                    // Jersey
                    RoundedRectangle(cornerRadius: 10)
                        .fill(jerseyColor)
                        .frame(width: 50, height: 50)
                    
                    // Rain jacket overlay
                    if weather?.condition == .rainy || weather?.condition == .stormy {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.yellow.opacity(0.7))
                            .frame(width: 54, height: 52)
                    }
                }
                
                // Bike
                bikeView
                    .offset(y: -10)
            }
            .offset(y: isAnimating ? -5 : 5)
            .animation(.easeInOut(duration: 1.0).repeatForever(), value: isAnimating)
            
            // Weather effects
            weatherEffects
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private var sceneBackground: some View {
        ZStack {
            // Road
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 60)
                .offset(y: 80)
            
            // Road markings
            HStack(spacing: 30) {
                ForEach(0..<5) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 30, height: 4)
                }
            }
            .offset(y: 80)
        }
    }
    
    private var sunglasses: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black)
                .frame(width: 12, height: 8)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black)
                .frame(width: 12, height: 8)
        }
        .offset(y: -2)
    }
    
    private var jerseyColor: LinearGradient {
        let temp = weather?.temperature ?? 20
        if temp < 10 {
            return LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
        } else if temp < 20 {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom)
        }
    }
    
    private var bikeView: some View {
        HStack(spacing: 35) {
            // Front wheel
            Circle()
                .stroke(Color.gray, lineWidth: 3)
                .frame(width: 35, height: 35)
            
            // Back wheel
            Circle()
                .stroke(Color.gray, lineWidth: 3)
                .frame(width: 35, height: 35)
        }
        .overlay(
            // Frame
            Path { path in
                path.move(to: CGPoint(x: 20, y: 20))
                path.addLine(to: CGPoint(x: 50, y: 0))
                path.addLine(to: CGPoint(x: 80, y: 20))
            }
            .stroke(Color.orange, lineWidth: 3)
        )
    }
    
    @ViewBuilder
    private var weatherEffects: some View {
        switch weather?.condition {
        case .rainy, .stormy:
            RainEffect()
        case .snowy:
            SnowEffect()
        case .sunny:
            SunRaysEffect()
        default:
            EmptyView()
        }
    }
}

// MARK: - Weather Effects

struct RainEffect: View {
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<20, id: \.self) { i in
                RainDrop()
                    .offset(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: CGFloat.random(in: 0...geometry.size.height)
                    )
            }
        }
    }
}

struct RainDrop: View {
    @State private var offset: CGFloat = -100
    
    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.5))
            .frame(width: 2, height: 15)
            .offset(y: offset)
            .onAppear {
                withAnimation(.linear(duration: Double.random(in: 0.5...1.0)).repeatForever(autoreverses: false)) {
                    offset = 300
                }
            }
    }
}

struct SnowEffect: View {
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<15, id: \.self) { _ in
                SnowFlake()
                    .offset(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: CGFloat.random(in: 0...geometry.size.height)
                    )
            }
        }
    }
}

struct SnowFlake: View {
    @State private var offset: CGFloat = -50
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "snowflake")
            .foregroundColor(.white.opacity(0.8))
            .font(.caption)
            .rotationEffect(.degrees(rotation))
            .offset(y: offset)
            .onAppear {
                withAnimation(.linear(duration: Double.random(in: 2...4)).repeatForever(autoreverses: false)) {
                    offset = 300
                    rotation = 360
                }
            }
    }
}

struct SunRaysEffect: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 60))
            .foregroundColor(.yellow.opacity(0.3))
            .rotationEffect(.degrees(rotation))
            .offset(x: 100, y: -80)
            .onAppear {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Supporting Views

struct ClothingItemCard: View {
    let item: ClothingRecommendation
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: getSystemIcon(for: item.icon))
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Text(item.item)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Circle()
                .fill(item.priority.color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func getSystemIcon(for icon: String) -> String {
        switch icon {
        case "helmet": return "shield.checkered"
        case "tshirt.fill": return "tshirt.fill"
        case "jacket.fill": return "cloud.sun.fill"
        case "hand.raised.fill": return "hand.raised.fill"
        case "figure.walk": return "figure.walk"
        case "figure.arms.open": return "figure.arms.open"
        case "sun.max.fill": return "sun.max.fill"
        case "cloud.rain.fill": return "cloud.rain.fill"
        case "shoe.fill": return "shoe.fill"
        case "eyeglasses": return "eyeglasses"
        case "sunglasses.fill": return "sunglasses.fill"
        case "wind": return "wind"
        case "exclamationmark.triangle.fill": return "exclamationmark.triangle.fill"
        default: return "questionmark"
        }
    }
}

struct HourlyForecastCard: View {
    let forecast: HourlyForecast
    
    var body: some View {
        VStack(spacing: 8) {
            Text(forecast.hour)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            
            Image(systemName: forecast.condition.icon)
                .font(.title2)
                .foregroundColor(forecast.condition.color)
            
            Text("\(Int(forecast.temperature))Â°")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            if forecast.precipitation > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.caption2)
                    Text("\(forecast.precipitation)%")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.cyan)
            }
        }
        .frame(width: 60)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}

struct DailyForecastRow: View {
    let forecast: DailyForecast
    
    var body: some View {
        HStack {
            Text(forecast.day)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .leading)
            
            Spacer()
            
            if forecast.precipitation > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                    Text("\(forecast.precipitation)%")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.cyan)
                .frame(width: 50)
            } else {
                Spacer()
                    .frame(width: 50)
            }
            
            Image(systemName: forecast.condition.icon)
                .font(.title3)
                .foregroundColor(forecast.condition.color)
                .frame(width: 30)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("\(Int(forecast.low))Â°")
                    .foregroundColor(.white.opacity(0.6))
                
                // Temperature bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * tempBarWidth)
                    }
                }
                .frame(width: 60, height: 4)
                
                Text("\(Int(forecast.high))Â°")
                    .foregroundColor(.white)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
        }
        .padding(.vertical, 12)
    }
    
    private var tempBarWidth: CGFloat {
        let range = forecast.high - forecast.low
        let maxRange: Double = 20
        return CGFloat(min(range / maxRange, 1.0))
    }
}

struct WeatherDetailCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.white.opacity(0.8))
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}

#Preview {
    WeatherView()
        .environmentObject(WeatherService())
        .environmentObject(BluetoothManager())
}
