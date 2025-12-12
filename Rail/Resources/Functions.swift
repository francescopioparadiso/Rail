import Foundation
import MapKit
import WeatherKit
import CoreLocation
import Vision
import CoreImage.CIFilterBuiltins

func romanToArabic(platform: String) -> String {
    let roman = ["XX", "XIX", "XVIII", "XVII", "XVI", "XV", "XIV", "XIII", "XII", "XI", "X", "IX", "VIII", "VII", "VI", "V", "IV", "III", "II", "I"]
    let arabic = ["20", "19", "18", "17", "16", "15", "14", "13", "12", "11", "10", "9", "8", "7", "6", "5", "4", "3", "2", "1"]

    let parts = platform.split(separator: " ")
    if parts.count < 2 {
        if platform == "-" || platform.allSatisfy({ $0.isNumber }) {
            return platform
        } else {
            var result = platform
            let sortedPairs = zip(roman, arabic)
            for (romanNumeral, arabicNumeral) in sortedPairs {
                result = result.replacingOccurrences(of: romanNumeral, with: arabicNumeral)
            }
            return result
        }
    } else {
        var firstPart = String(parts[0])
        let secondPart = String(parts[1])

        // Only convert the first part
        let sortedPairs = zip(roman, arabic)
        for (romanNumeral, arabicNumeral) in sortedPairs {
            firstPart = firstPart.replacingOccurrences(of: romanNumeral, with: arabicNumeral)
        }

        if secondPart == "TR" {
            return firstPart + " /"
        } else {
            return firstPart + " " + secondPart
        }
    }
}

func adjust_date(actual_date: Date, previous_date: Date?, selected_date: Date) -> Date {
    let calendar = Calendar.current
    // map actual time (hour/minute) onto the selected_date
    let hour = calendar.component(.hour, from: actual_date)
    let minute = calendar.component(.minute, from: actual_date)
    var current = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selected_date)!
    
    // if no previous adjusted date -> base on selected_date
    guard let previousAdjusted = previous_date else {
        return current
    }
    
    // if current is not strictly after previousAdjusted, add days until it is
    while current <= previousAdjusted {
        current = calendar.date(byAdding: .day, value: 1, to: current)!
    }
    
    return current
}

func time_to_date(timeString: String) -> Date? {
    if timeString == "" || timeString == "01:00" {
        return .distantPast
    }
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm"
    timeFormatter.locale = Locale(identifier: "it_IT_POSIX")
    timeFormatter.timeZone = TimeZone(secondsFromGMT: 3600) // Interpret time string in GMT
    
    let time = timeFormatter.date(from: timeString.trimmingCharacters(in: .whitespaces))
    
    let calendar = Calendar.current
    let now = Date()
    
    let hour = calendar.component(.hour, from: time!)
    let minute = calendar.component(.minute, from: time!)
    
    if let todayWithTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) {
        return todayWithTime
    } else {
        return nil
    }
}

func distance_between_stations(from station1: String, to station2: String) -> Int? {
    guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv") else {
        print("❌ Error: stations.csv not found in bundle")
        return nil
    }

    do {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let rows = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var coord1: CLLocationCoordinate2D?
        var coord2: CLLocationCoordinate2D?

        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let latitude = columns[0]
            let longitude = columns[1]
            let name = columns[2]

            if name.contains("|") {
                for name in name.split(separator: "|") {
                    if name == station1.lowercased() {
                        coord1 = CLLocationCoordinate2D(latitude: Double(latitude) ?? 0, longitude: Double(longitude) ?? 0)
                    } else if name == station2.lowercased() {
                        coord2 = CLLocationCoordinate2D(latitude: Double(latitude) ?? 0, longitude: Double(longitude) ?? 0)
                    }
                }
            } else {
                if name == station1.lowercased() {
                    coord1 = CLLocationCoordinate2D(latitude: Double(latitude) ?? 0, longitude: Double(longitude) ?? 0)
                } else if name == station2.lowercased() {
                    coord2 = CLLocationCoordinate2D(latitude: Double(latitude) ?? 0, longitude: Double(longitude) ?? 0)
                }
            }

            if coord1 != nil && coord2 != nil {
                break
            }
        }

        if let c1 = coord1, let c2 = coord2 {
            let location1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
            let location2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
            let distanceInMeters = location1.distance(from: location2)
            return Int(round(distanceInMeters / 1000))
        } else {
            print("❌ Error: One or both stations not found")
        }

    } catch {
        print("❌ Error reading CSV file: \(error)")
    }

    return nil
}

// MARK: - Map Functions
func get_latitude(for station: String) -> Double {
    guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv") else {
        print("❌ Error: stations.csv not found in bundle")
        return 0
    }

    do {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let rows = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let latitude = columns[0]
            let name = columns[2]

            if name.contains("|") {
                for name in name.split(separator: "|") {
                    if name == station.lowercased() {
                        return Double(latitude) ?? 0
                    }
                }
            } else {
                if name == station.lowercased() {
                    return Double(latitude) ?? 0
                }
            }
        }
    } catch {
        print("❌ Error reading CSV file: \(error)")
    }

    return 0
}

func get_longitude(for station: String) -> Double {
    guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv") else {
        print("❌ Error: stations.csv not found in bundle")
        return 0
    }

    do {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let rows = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let longitude = columns[1]
            let name = columns[2]

            if name.contains("|") {
                for name in name.split(separator: "|") {
                    if name == station.lowercased() {
                        return Double(longitude) ?? 0
                    }
                }
            } else {
                if name == station.lowercased() {
                    return Double(longitude) ?? 0
                }
            }
        }
    } catch {
        print("❌ Error reading CSV file: \(error)")
    }

    return 0
}

// MARK: - Weather Functions
/// Apple Weather
func getAppleWeather(lat: Double, lon: Double, date: Date) async throws -> String {
    // 1. Safety Check: Don't fetch weather for valid invalid coordinates (0,0)
    guard lat != 0, lon != 0 else {
        return "—"
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

    return "\(emoji) \(temp)°C"
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

/// Open Meteo
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
    
    // 2. Decide if we need the Forecast API (future/today) or Archive API (past)
    let isPast = date < Calendar.current.startOfDay(for: Date())
    let baseUrl = isPast ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast"
    
    // 3. Construct the URL
    // We ask for hourly temperature and weathercode for the specific date
    guard let url = URL(string: "\(baseUrl)?latitude=\(lat)&longitude=\(lon)&start_date=\(dateString)&end_date=\(dateString)&hourly=temperature_2m,weathercode") else {
        return "—"
    }
    
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
    let emoji = wmoToEmoji(code: code)
    
    return "\(emoji) \(temp)°C"
}

func wmoToEmoji(code: Int) -> String {
    switch code {
    case 0: return "☀️" // Clear sky
    case 1, 2, 3: return "🌤️" // Mainly clear, partly cloudy, and overcast
    case 45, 48: return "🌫️" // Fog
    case 51, 53, 55: return "🌦️" // Drizzle
    case 61, 63, 65: return "🌧️" // Rain
    case 71, 73, 75: return "❄️" // Snow
    case 95, 96, 99: return "⛈️" // Thunderstorm
    default: return "🌡️"
    }
}

// MARK: - Ticket Image functions
func symbolToString(_ code: VNBarcodeSymbology) -> String {
    switch code {
    case .aztec:
        return "aztec"
    case .qr:
        return "qr"
    default:
        return "aztec"
    }
}

func stringToSymbol(_ string: String) -> VNBarcodeSymbology {
    switch string {
    case "aztec":
        return .aztec
    case "qr":
        return .qr
    default:
        return .aztec
    }
}

func fixOrientation(img: UIImage) -> UIImage? {
    if img.imageOrientation == .up { return img }
    
    UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
    img.draw(in: CGRect(origin: .zero, size: img.size))
    let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalizedImage
}
