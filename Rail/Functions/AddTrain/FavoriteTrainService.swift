import Foundation
import SwiftData
import WidgetKit

struct PreparedFavoriteTrain {
    let info: [String: Any]
    let fromStation: String
    let toStation: String
}

struct PreparedSolutionSegment {
    let info: [String: Any]
    let fromStation: String
    let toStation: String
    let dayOffset: Int
}

enum SolutionSegmentResolver {
    static func resolve(_ segment: SolutionSegment) async -> PreparedSolutionSegment? {
        let identifiers = await TrenitaliaAPI().train_list(number: segment.number, code: segment.stationCode)

        let segmentDay = Calendar.current.startOfDay(for: segment.departureTime)
        var targetIdentifier = identifiers.first
        var dayOffset = 0

        if let exactId = identifiers.first(where: { id in
            guard let tsString = id.split(separator: "/").last, let ms = Double(tsString) else { return false }
            return Calendar.current.isDate(Date(timeIntervalSince1970: ms / 1000), inSameDayAs: segmentDay)
        }) {
            targetIdentifier = exactId
        } else if let firstId = identifiers.first {
            if let tsString = firstId.split(separator: "/").last, let ms = Double(tsString) {
                let firstIdDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ms / 1000))
                dayOffset = Calendar.current.dateComponents([.day], from: firstIdDay, to: segmentDay).day ?? 0
            }
        }

        guard let identifier = targetIdentifier,
              let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false) else { return nil }

        return PreparedSolutionSegment(
            info: info,
            fromStation: segment.origin,
            toStation: segment.destination,
            dayOffset: dayOffset
        )
    }

    static func resolveAll(_ segments: [SolutionSegment]) async -> [PreparedSolutionSegment] {
        await withTaskGroup(of: (Int, PreparedSolutionSegment?).self) { group in
            for (index, segment) in segments.enumerated() {
                group.addTask {
                    let prepared = await resolve(segment)
                    return (index, prepared)
                }
            }

            var results: [(Int, PreparedSolutionSegment)] = []
            for await (index, prepared) in group {
                if let prepared {
                    results.append((index, prepared))
                }
            }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }
    }
}

enum FavoriteTrainService {
    static func loadTodayTrain(for favorite: Favorite) async -> PreparedFavoriteTrain? {
        let fromStation = favorite.stop_names.first ?? ""
        let toStation = favorite.stop_names.last ?? ""
        guard !fromStation.isEmpty, !toStation.isEmpty else { return nil }

        if favorite.provider == "italo" {
            if let info = await ItaloAPI().info(identifier: favorite.number, should_fetch_weather: false),
               trainContainsSegment(info: info, from: fromStation, to: toStation) {
                return PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation)
            }
            return nil
        }

        if !favorite.identifier.isEmpty {
            let identifier = adjustedIdentifierForToday(favorite.identifier)
            if let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false),
               trainContainsSegment(info: info, from: fromStation, to: toStation) {
                return PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation)
            }
        }

        if let prepared = await firstMatchingTrainByNumber(
            number: favorite.number,
            fromStation: fromStation,
            toStation: toStation
        ) {
            return prepared
        }

        return await loadFromStationSearch(favorite: favorite, fromStation: fromStation, toStation: toStation)
    }

    @MainActor
    static func savePreparedTrain(
        _ prepared: PreparedFavoriteTrain,
        modelContext: ModelContext,
        profile: UserProfile?
    ) {
        let id = UUID()
        let info = prepared.info

        let train = Train(
            id: id,
            logo: info["logo"] as? String ?? "",
            number: info["number"] as? String ?? "",
            identifier: info["identifier"] as? String ?? "",
            provider: info["provider"] as? String ?? "",
            last_update_time: info["last_update_time"] as? Date ?? Date(),
            delay: info["delay"] as? Int ?? 0,
            direction: info["direction"] as? String ?? "",
            issue: info["issue"] as? String ?? ""
        )
        modelContext.insert(train)

        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.compactMap { $0["name"] as? String }
        let fromIdx = names.firstIndex(of: prepared.fromStation)
        let toIdx = names.firstIndex(of: prepared.toStation)

        var addedStops: [Stop] = []
        for (index, stop) in stops.enumerated() {
            let isSelected: Bool = {
                guard let fromIdx, let toIdx else { return false }
                return index >= fromIdx && index <= toIdx
            }()

            let stopToAdd = Stop(
                id: id,
                name: stop["name"] as? String ?? "",
                platform: stop["platform"] as? String ?? "",
                weather: stop["weather"] as? String ?? "",
                is_selected: isSelected,
                status: stop["status"] as? Int ?? 0,
                is_completed: stop["is_completed"] as? Bool ?? false,
                is_in_station: stop["is_in_station"] as? Bool ?? false,
                dep_delay: stop["dep_delay"] as? Int ?? 0,
                arr_delay: stop["arr_delay"] as? Int ?? 0,
                dep_time_id: stop["dep_time_id"] as? Date ?? .distantPast,
                arr_time_id: stop["arr_time_id"] as? Date ?? .distantPast,
                dep_time_eff: stop["dep_time_eff"] as? Date ?? .distantPast,
                arr_time_eff: stop["arr_time_eff"] as? Date ?? .distantPast,
                ref_time: stop["ref_time"] as? Date ?? .distantPast
            )
            modelContext.insert(stopToAdd)
            addedStops.append(stopToAdd)
        }

        try? modelContext.save()

        if let profile, profile.calendarSettings.autoSyncToCalendar {
            let settings = profile.calendarSettings
            Task {
                await CalendarManager.shared.syncTrainEvent(
                    train: train,
                    stops: addedStops,
                    seats: [],
                    titleFormat: settings.titleFormat,
                    calendarIdentifier: settings.calendarIdentifier,
                    travelTime: settings.travelTime
                )
            }
        }

        reload_widget_timelines()
    }

    private static func adjustedIdentifierForToday(_ identifier: String) -> String {
        let components = identifier.split(separator: "/").map(String.init)
        guard components.count > 1, let timestamp = Int(components.last ?? "") else { return identifier }

        let storedDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        let today = Calendar.current.startOfDay(for: Date())
        let dayDifference = Calendar.current.dateComponents([.day], from: storedDay, to: today).day ?? 0
        let adjustedTimestamp = Int(
            Date(timeIntervalSince1970: TimeInterval(timestamp))
                .addingTimeInterval(TimeInterval(dayDifference) * 86_400)
                .timeIntervalSince1970
        )
        return components.dropLast().joined(separator: "/") + "/\(adjustedTimestamp)"
    }

    nonisolated static func trainContainsSegment(info: [String: Any], from: String, to: String) -> Bool {
        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.compactMap { $0["name"] as? String }
        guard let fromIdx = names.firstIndex(of: from),
              let toIdx = names.firstIndex(of: to) else { return false }
        return fromIdx <= toIdx
    }

    private static func firstMatchingTrainByNumber(
        number: String,
        fromStation: String,
        toStation: String
    ) async -> PreparedFavoriteTrain? {
        guard let url = URL(
            string: "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(number)"
        ) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let resultString = String(data: data, encoding: .utf8) else { return nil }

            let lines = resultString.split(separator: "\n")
            let todayTimestamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) * 1000

            return await withTaskGroup(of: PreparedFavoriteTrain?.self) { group in
                for line in lines {
                    let parts = line.split(separator: "|")
                    guard parts.count > 1 else { continue }

                    let codeParts = parts[1].split(separator: "-")
                    guard codeParts.count > 2 else { continue }

                    let code = codeParts[1]
                    let timestamp = Int(codeParts[2]) ?? 0
                    guard timestamp >= todayTimestamp else { continue }

                    let identifier = "\(code)/\(number)/\(timestamp)"
                    group.addTask {
                        guard let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false),
                              trainContainsSegment(info: info, from: fromStation, to: toStation) else { return nil }
                        return PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation)
                    }
                }

                if !number.isEmpty {
                    group.addTask {
                        guard let info = await ItaloAPI().info(identifier: number, should_fetch_weather: false),
                              trainContainsSegment(info: info, from: fromStation, to: toStation) else { return nil }
                        return PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation)
                    }
                }

                for await result in group {
                    if let result {
                        group.cancelAll()
                        return result
                    }
                }
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func loadFromStationSearch(
        favorite: Favorite,
        fromStation: String,
        toStation: String
    ) async -> PreparedFavoriteTrain? {
        async let departureSuggestions = TrenitaliaAPI().station_autocomplete(name: fromStation)
        async let arrivalSuggestions = TrenitaliaAPI().station_autocomplete(name: toStation)
        let (departureResults, arrivalResults) = await (departureSuggestions, arrivalSuggestions)
        guard let departureCode = departureResults.first?.code,
              let arrivalCode = arrivalResults.first?.code else { return nil }

        let solutions = await TrenitaliaAPI().train_solutions(
            departureLocationId: departureCode,
            arrivalLocationId: arrivalCode,
            departureTime: Date()
        )

        guard let targetDeparture = favorite.stop_ref_times.first else {
            return await bestSolutionTrain(from: solutions, fromStation: fromStation, toStation: toStation)
        }

        let bestSegment = solutions
            .flatMap(\.segments)
            .min(by: {
                abs($0.departureTime.timeIntervalSince(targetDeparture)) <
                abs($1.departureTime.timeIntervalSince(targetDeparture))
            })

        if let segment = bestSegment {
            return await loadSegment(segment, fromStation: fromStation, toStation: toStation)
        }

        return await bestSolutionTrain(from: solutions, fromStation: fromStation, toStation: toStation)
    }

    private static func bestSolutionTrain(
        from solutions: [Solution],
        fromStation: String,
        toStation: String
    ) async -> PreparedFavoriteTrain? {
        for solution in solutions {
            for segment in solution.segments {
                if segment.origin == fromStation, segment.destination == toStation,
                   let prepared = await loadSegment(segment, fromStation: fromStation, toStation: toStation) {
                    return prepared
                }
            }
        }
        return nil
    }

    private static func loadSegment(
        _ segment: SolutionSegment,
        fromStation: String,
        toStation: String
    ) async -> PreparedFavoriteTrain? {
        guard let prepared = await SolutionSegmentResolver.resolve(segment),
              trainContainsSegment(info: prepared.info, from: fromStation, to: toStation) else { return nil }

        return PreparedFavoriteTrain(
            info: prepared.info,
            fromStation: fromStation,
            toStation: toStation
        )
    }
}
