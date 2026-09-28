import Foundation
import CoreLocation

enum StationLookup {
    /// Every station once, under the first of its names.
    private nonisolated static let stations: [(name: String, lat: Double, lon: Double)] = buildStations()
    private nonisolated static let coordinatesByName: [String: (lat: Double, lon: Double)] = buildIndex()

    /// Builds the CSV index on a background thread so the first
    /// `distanceBetweenStations` call doesn't block the main thread.
    nonisolated static func warmUp() {
        Task.detached(priority: .utility) {
            _ = coordinatesByName.count
        }
    }

    private static func buildStations() -> [(name: String, lat: Double, lon: Double)] {
        guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv"),
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("❌ Error: stations.csv not found in bundle")
            return []
        }

        return content.components(separatedBy: "\n").dropFirst().filter({ !$0.isEmpty }).compactMap { row in
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 3,
                  let lat = Double(columns[0]),
                  let lon = Double(columns[1]) else { return nil }
            return (name: columns[2], lat: lat, lon: lon)
        }
    }

    private static func buildIndex() -> [String: (lat: Double, lon: Double)] {
        var index: [String: (lat: Double, lon: Double)] = [:]
        for station in stations {
            let coord = (lat: station.lat, lon: station.lon)
            for variant in station.name.split(separator: "|") {
                index[String(variant)] = coord
            }
        }
        return index
    }

    nonisolated static func coordinates(for station: String) -> (lat: Double, lon: Double)? {
        coordinatesByName[station.lowercased()]
    }

    /// The `limit` stations closest to `location`, nearest first, by the first of
    /// their names in lowercase.
    nonisolated static func nearestStations(to location: CLLocation, limit: Int) -> [String] {
        stations
            .map { station in
                let distance = location.distance(from: CLLocation(latitude: station.lat, longitude: station.lon))
                return (name: station.name, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .compactMap { $0.name.split(separator: "|").first.map(String.init) }
    }
}

nonisolated func distanceBetweenStations(from station1: String, to station2: String) -> Int? {
    guard let c1 = StationLookup.coordinates(for: station1),
          let c2 = StationLookup.coordinates(for: station2) else {
        return nil
    }

    let location1 = CLLocation(latitude: c1.lat, longitude: c1.lon)
    let location2 = CLLocation(latitude: c2.lat, longitude: c2.lon)
    return Int(round(location1.distance(from: location2) / 1000))
}

nonisolated func getLatitude(for station: String) -> Double {
    StationLookup.coordinates(for: station)?.lat ?? 0
}

nonisolated func getLongitude(for station: String) -> Double {
    StationLookup.coordinates(for: station)?.lon ?? 0
}
