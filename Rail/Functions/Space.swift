import Foundation
import CoreLocation

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
