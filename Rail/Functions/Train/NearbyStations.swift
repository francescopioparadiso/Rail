import Foundation
import CoreLocation

/// The stations closest to where the user is, offered before anything is typed so
/// the station they are standing at is one tap away.
enum NearbyStations {
    // MARK: - Methods

    /// The closest stations, nearest first, each resolved by `resolve` into the
    /// suggestion the caller's search would have produced. Stations `resolve`
    /// can't find are left out; nothing comes back without the user's location.
    static func suggestions(
        limit: Int = 5,
        resolve: @escaping @MainActor (String) async -> StationSuggestion?
    ) async -> [StationSuggestion] {
        guard let location = await currentLocation() else { return [] }
        let names = StationLookup.nearestStations(to: location, limit: limit)

        let resolved = await withTaskGroup(of: (Int, StationSuggestion?).self) { group in
            for (index, name) in names.enumerated() {
                group.addTask { (index, await resolve(name)) }
            }
            var byIndex: [Int: StationSuggestion] = [:]
            for await (index, suggestion) in group {
                byIndex[index] = suggestion
            }
            return byIndex
        }

        // two names can resolve to the same station, which only needs showing once
        var seen: Set<StationSuggestion> = []
        return names.indices.compactMap { resolved[$0] }.filter { seen.insert($0).inserted }
    }

    // MARK: - Helpers

    /// One fix of where the user is, asking for permission the first time. Nil when
    /// location is off or refused.
    private static func currentLocation() async -> CLLocation? {
        // held for as long as the fix is awaited, and what raises the prompt
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
            }
        } catch {
            print("Error fetching current location: \(error)")
        }
        return nil
    }
}
