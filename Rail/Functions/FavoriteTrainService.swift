import Foundation
import SwiftData
import WidgetKit

struct PreparedFavoriteTrain {
    let info: [String: Any]
    let fromStation: String
    let toStation: String
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

        WidgetCenter.shared.reloadAllTimelines()
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

    static func trainContainsSegment(info: [String: Any], from: String, to: String) -> Bool {
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
        let identifiers = await TrenitaliaAPI().train_list(number: segment.number, code: segment.stationCode)
        let segmentDay = Calendar.current.startOfDay(for: segment.departureTime)

        var targetIdentifier = identifiers.first
        if let exactId = identifiers.first(where: { id in
            guard let tsString = id.split(separator: "/").last, let ms = Double(tsString) else { return false }
            return Calendar.current.isDate(Date(timeIntervalSince1970: ms / 1000), inSameDayAs: segmentDay)
        }) {
            targetIdentifier = exactId
        }

        guard let identifier = targetIdentifier,
              let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false),
              trainContainsSegment(info: info, from: fromStation, to: toStation) else { return nil }

        return PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation)
    }
}
