import Foundation
import CoreLocation

enum StationLookup {
    private nonisolated static let coordinatesByName: [String: (lat: Double, lon: Double)] = buildIndex()

    /// Builds the CSV index on a background thread so the first
    /// `distanceBetweenStations` call doesn't block the main thread.
    nonisolated static func warmUp() {
        Task.detached(priority: .utility) {
            _ = coordinatesByName.count
        }
    }

    private static func buildIndex() -> [String: (lat: Double, lon: Double)] {
        guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv"),
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("❌ Error: stations.csv not found in bundle")
            return [:]
        }

        var index: [String: (lat: Double, lon: Double)] = [:]
        for row in content.components(separatedBy: "\n").dropFirst().filter({ !$0.isEmpty }) {
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 3,
                  let lat = Double(columns[0]),
                  let lon = Double(columns[1]) else { continue }

            let coord = (lat: lat, lon: lon)
            let nameField = columns[2]

            if nameField.contains("|") {
                for variant in nameField.split(separator: "|") {
                    index[String(variant)] = coord
                }
            } else {
                index[nameField] = coord
            }
        }
        return index
    }

    nonisolated static func coordinates(for station: String) -> (lat: Double, lon: Double)? {
        coordinatesByName[station.lowercased()]
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
