import Foundation
import CoreLocation
import WeatherKit

// MARK: - Cache
private class WeatherCache {
    static let shared = WeatherCache()
    private var cache: [String: (String, Date)] = [:]
    private let lock = NSLock()
    
    func get(lat: Double, lon: Double, date: Date) -> String? {
        let key = cacheKey(lat: lat, lon: lon, date: date)
        lock.lock()
        defer { lock.unlock() }
        
        if let (value, timestamp) = cache[key] {
            // Cache for 1 hour
            if Date().timeIntervalSince(timestamp) < 3600 {
                return value
            }
        }
        return nil
    }
    
    func set(lat: Double, lon: Double, date: Date, value: String) {
        let key = cacheKey(lat: lat, lon: lon, date: date)
        lock.lock()
        defer { lock.unlock() }
        cache[key] = (value, Date())
    }
    
    private func cacheKey(lat: Double, lon: Double, date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let day = Calendar.current.startOfDay(for: date)
        return "\(lat),\(lon),\(day.timeIntervalSince1970),\(hour)"
    }
}

func get_weather(lat: Double, lon: Double, date: Date) async throws -> String {
    // 1. Validation & Setup
    guard lat != 0, lon != 0 else { return "—" }
    
    if let cached = WeatherCache.shared.get(lat: lat, lon: lon, date: date) {
        return cached
    }
    
    let isoDate = DateFormatter()
    isoDate.dateFormat = "yyyy-MM-dd"
    let dayStr = isoDate.string(from: date)
    
    // 2. Determine Endpoint (Archive for past, Forecast for future)
    let isPast = date < Calendar.current.startOfDay(for: Date())
    let host = isPast ? "archive-api.open-meteo.com/v1/archive" : "api.open-meteo.com/v1/forecast"
    
    guard let url = URL(string: "https://\(host)?latitude=\(lat)&longitude=\(lon)&start_date=\(dayStr)&end_date=\(dayStr)&hourly=temperature_2m,weathercode") else { return "—" }

    // 3. Fetch & Decode
    let (data, _) = try await URLSession.shared.data(from: url)
    let res = try JSONDecoder().decode(OMResponse.self, from: data)
    
    // 4. Extract specific hour
    let hourIndex = Calendar.current.component(.hour, from: date)
    guard res.hourly.temperature_2m.indices.contains(hourIndex) else { return "—" }
    
    let temp = Int(res.hourly.temperature_2m[hourIndex].rounded())
    let emoji = res.hourly.weathercode[hourIndex].weatherEmoji
    
    let result = "\(emoji) \(temp)°C"
    WeatherCache.shared.set(lat: lat, lon: lon, date: date, value: result)
    return result
}

private struct OMResponse: Decodable {
    let hourly: Hourly
    struct Hourly: Decodable {
        let temperature_2m: [Double]
        let weathercode: [Int]
    }
}

private extension Int {
    var weatherEmoji: String {
        switch self {
        case 0: return "☀️"
        case 1...3: return "🌤️"
        case 45, 48: return "🌫️"
        case 51...57: return "🌦️"
        case 61...67: return "🌧️"
        case 71...77: return "❄️"
        case 95...99: return "⛈️"
        default: return "🌡️"
        }
    }
}

// MARK: - Apple WeatherKit
func getAppleWeather(lat: Double, lon: Double, date: Date) async throws -> String {
    // 1. Safety Check: Don't fetch weather for valid invalid coordinates (0,0)
    guard lat != 0, lon != 0 else {
        return "—"
    }
    
    if let cached = WeatherCache.shared.get(lat: lat, lon: lon, date: date) {
        return cached
    }
    
    let location = CLLocation(latitude: lat, longitude: lon)
    
    // 2. Optimization: Fetch ONLY the hourly forecast (saves data/processing)
    // Note: This defaults to current/future forecast.
    let hourly = try await WeatherService.shared.weather(for: location, including: .hourly)

    // 3. Find the forecast hour closest to the specified date
    guard let forecast = hourly.first(where: { hour in
        let delta = abs(hour.date.timeIntervalSince(date))
        return delta < 60 * 60  // within 1 hour
    }) else {
        // If the date is too far in the past or future, WeatherKit returns nothing relevant.
        return "—"
    }

    let temp = Int(forecast.temperature.value.rounded())
    let emoji = weatherEmoji(from: forecast.condition)

    let result = "\(emoji) \(temp)°C"
    WeatherCache.shared.set(lat: lat, lon: lon, date: date, value: result)
    return result
}

func weatherEmoji(from condition: WeatherCondition) -> String {
    switch condition {
    case .clear: return "☀️"
    case .mostlyClear, .partlyCloudy: return "🌤️"
    case .cloudy: return "☁️"
    case .foggy: return "🌫️"
    case .drizzle: return "🌦️"
    case .rain: return "🌧️"
    case .thunderstorms: return "⛈️"
    case .snow: return "❄️"
    default: return "🌡️"
    }
}

// MARK: - Open Meteo
struct OpenMeteoResponse: Codable {
    let hourly: Hourly
}

struct Hourly: Codable {
    let time: [String]
    let temperature_2m: [Double]
    let weathercode: [Int]
}

func getOpenMeteoWeather(lat: Double, lon: Double, date: Date) async throws -> String {
    // 1. Format the date to YYYY-MM-DD for the API
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let dateString = dateFormatter.string(from: date)
    
    if let cached = WeatherCache.shared.get(lat: lat, lon: lon, date: date) {
        return cached
    }
    
    // 2. Decide if we need the Forecast API (future/today) or Archive API (past)
    let isPast = date < Calendar.current.startOfDay(for: Date())
    let baseUrl = isPast ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast"
    
    // 3. Construct the URL
    // We ask for hourly temperature and weathercode for the specific date
    guard let url = URL(string: "\(baseUrl)?latitude=\(lat)&longitude=\(lon)&start_date=\(dateString)&end_date=\(dateString)&hourly=temperature_2m,weathercode") else {
        return "—"
    }
    print("Fetching weather from URL: \(url.absoluteString)")
    
    // 4. Fetch Data
    let (data, _) = try await URLSession.shared.data(from: url)
    let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    
    // 5. Find the index for the specific hour
    let calendar = Calendar.current
    let targetHour = calendar.component(.hour, from: date)
    
    // The API returns 00:00 to 23:00. We just grab the index matching the hour.
    // Safety check: ensure the array has enough elements
    guard decoded.hourly.temperature_2m.indices.contains(targetHour) else {
        return "—"
    }
    
    let temp = Int(decoded.hourly.temperature_2m[targetHour].rounded())
    let code = decoded.hourly.weathercode[targetHour]
    let emoji = getWeatherEmoji(code: code)
    
    print("\(lat), \(lon) at \(date): Code \(code), Temp \(temp)°C")
    let result = "\(emoji) \(temp)°C"
    WeatherCache.shared.set(lat: lat, lon: lon, date: date, value: result)
    return result
}

func getWeatherEmoji(code: Int) -> String {
    switch code {
    case 200...232: return "⛈️" // Thunderstorm
    case 300...321: return "🌧️" // Drizzle
    case 500...531: return "🌧️" // Rain
    case 600...622: return "❄️" // Snow
    case 701...781: return "🌫️" // Atmosphere (Fog, Mist)
    case 800:       return "☀️" // Clear
    case 801...804: return "☁️" // Clouds
    default:        return "🌡️"
    }
}
