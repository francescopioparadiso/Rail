import Foundation

// MARK: - Cache
private class WeatherCache {
    // MARK: - Properties

    static let shared = WeatherCache()
    private var cache: [String: (String, Date)] = [:]
    private let lock = NSLock()

    // MARK: - Methods

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

func getWeather(lat: Double, lon: Double, date: Date) async throws -> String {
    guard lat != 0, lon != 0 else { return "—" }
    
    if let cached = WeatherCache.shared.get(lat: lat, lon: lon, date: date) {
        return cached
    }
    
    let isoDate = DateFormatter()
    isoDate.dateFormat = "yyyy-MM-dd"
    let dayStr = isoDate.string(from: date)
    
    let isPast = date < Calendar.current.startOfDay(for: Date())
    let host = isPast ? "archive-api.open-meteo.com/v1/archive" : "api.open-meteo.com/v1/forecast"
    
    guard let url = URL(string: "https://\(host)?latitude=\(lat)&longitude=\(lon)&start_date=\(dayStr)&end_date=\(dayStr)&hourly=temperature_2m,weathercode") else { return "—" }

    let (data, _) = try await URLSession.shared.data(from: url)
    let res = try JSONDecoder().decode(OMResponse.self, from: data)
    
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
