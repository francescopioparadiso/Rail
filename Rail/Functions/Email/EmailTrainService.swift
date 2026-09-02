import Foundation
import SwiftData

struct PreparedEmailTrain {
    let prepared: PreparedFavoriteTrain
    let passengers: [EmailContentPassenger]
}

enum EmailTrainService {
    static func loadTrain(for ticket: EmailContent) async -> PreparedEmailTrain? {
        let fromStation = ticket.departureStation
        let toStation = ticket.arrivalStation
        guard !ticket.trainNumber.isEmpty, !fromStation.isEmpty, !toStation.isEmpty else { return nil }

        let departureDay = ticket.departureDate ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        // Near-term: viaggiatreno may already expose the exact service day.
        let results = await fetchCommonTrainList(number: ticket.trainNumber)
        let matching = results.filter {
            trainContainsSegmentFuzzy(info: $0, from: fromStation, to: toStation)
        }
        if let best = matching.first(where: {
            matchesDepartureDay(info: $0, departureDay: departureDay, fromStation: fromStation, calendar: calendar)
        }) {
            let stations = matchedStationNames(in: best, from: fromStation, to: toStation)
            return PreparedEmailTrain(
                prepared: PreparedFavoriteTrain(info: best, fromStation: stations.from, toStation: stations.to),
                passengers: ticket.passengers
            )
        }

        // Future tickets: lefrecce solutions know the day, but viaggiatreno only has a
        // recent template. Resolve that template and shift dates by dayOffset.
        let departureSuggestions = await TrenitaliaAPI().stationAutocomplete(name: fromStation)
        let arrivalSuggestions = await TrenitaliaAPI().stationAutocomplete(name: toStation)
        guard let departureCode = departureSuggestions.first?.code,
              let arrivalCode = arrivalSuggestions.first?.code else { return nil }

        let solutions = await TrenitaliaAPI().trainSolutions(
            departureLocationId: departureCode,
            arrivalLocationId: arrivalCode,
            departureTime: departureDay
        )

        let bestSegment = solutions
            .flatMap(\.segments)
            .filter {
                trainNumbersMatch($0.number, ticket.trainNumber)
                    && stationsMatch($0.origin, fromStation)
                    && stationsMatch($0.destination, toStation)
            }
            .min(by: {
                abs($0.departureTime.timeIntervalSince(departureDay)) <
                abs($1.departureTime.timeIntervalSince(departureDay))
            })

        guard let segment = bestSegment,
              let resolved = await SolutionSegmentResolver.resolve(segment) else { return nil }

        guard trainContainsSegmentFuzzy(info: resolved.info, from: fromStation, to: toStation)
                || trainContainsSegmentFuzzy(info: resolved.info, from: segment.origin, to: segment.destination)
        else { return nil }

        let shifted = applyDayOffset(
            to: resolved.info,
            dayOffset: resolved.dayOffset,
            targetDeparture: departureDay,
            calendar: calendar
        )
        let stations = matchedStationNames(in: shifted, from: fromStation, to: toStation)
        return PreparedEmailTrain(
            prepared: PreparedFavoriteTrain(
                info: shifted,
                fromStation: stations.from,
                toStation: stations.to
            ),
            passengers: ticket.passengers
        )
    }

    @MainActor
    static func savePreparedTrain(
        _ emailTrain: PreparedEmailTrain,
        sourceTicketID: UUID,
        modelContext: ModelContext,
        profile: UserProfile?
    ) {
        let prepared = emailTrain.prepared
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
            issue: info["issue"] as? String ?? "",
            sourceEmailTicketID: sourceTicketID
        )
        modelContext.insert(train)

        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.compactMap { $0["name"] as? String }
        let fromIdx = names.firstIndex(where: { stationsMatch($0, prepared.fromStation) })
        let toIdx = names.firstIndex(where: { stationsMatch($0, prepared.toStation) })

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

        var addedSeats: [Seat] = []
        let profileName = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for passenger in emailTrain.passengers {
            let seatName: String = {
                if emailTrain.passengers.count == 1, !profileName.isEmpty {
                    return profileName
                }
                return passenger.name
            }()
            let seat = Seat(
                id: UUID(),
                trainID: id,
                name: seatName,
                carriage: passenger.carriage == 0 ? "" : "\(passenger.carriage)",
                number: passenger.seat,
                image: passenger.qrcode.isEmpty ? nil : passenger.qrcode
            )
            modelContext.insert(seat)
            addedSeats.append(seat)
        }

        try? modelContext.save()

        if let profile, profile.calendarSettings.autoSyncToCalendar {
            let settings = profile.calendarSettings
            Task {
                await CalendarManager.shared.syncTrainEvent(
                    train: train,
                    stops: addedStops,
                    seats: addedSeats,
                    titleFormat: settings.titleFormat,
                    calendarIdentifier: settings.calendarIdentifier,
                    travelTime: settings.travelTime
                )
            }
        }

        reloadWidgetTimelines()
    }

    private static func applyDayOffset(
        to info: [String: Any],
        dayOffset: Int,
        targetDeparture: Date,
        calendar: Calendar
    ) -> [String: Any] {
        guard dayOffset != 0 else { return info }

        func offsetDate(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }

        var result = info
        result["delay"] = 0
        result["issue"] = ""
        result["last_update_time"] = offsetDate(info["last_update_time"] as? Date ?? Date())

        if let identifier = info["identifier"] as? String {
            let parts = identifier.split(separator: "/").map(String.init)
            if parts.count >= 3 {
                let targetDay = calendar.startOfDay(for: targetDeparture)
                let timestamp = Int(targetDay.timeIntervalSince1970 * 1000)
                result["identifier"] = parts.dropLast().joined(separator: "/") + "/\(timestamp)"
            }
        }

        let stops = info["stops"] as? [[String: Any]] ?? []
        result["stops"] = stops.map { stop -> [String: Any] in
            var shifted = stop
            let depID = stop["dep_time_id"] as? Date ?? .distantPast
            let arrID = stop["arr_time_id"] as? Date ?? .distantPast
            let ref = stop["ref_time"] as? Date ?? .distantPast
            shifted["status"] = 0
            shifted["is_completed"] = false
            shifted["is_in_station"] = false
            shifted["dep_delay"] = 0
            shifted["arr_delay"] = 0
            shifted["dep_time_id"] = offsetDate(depID)
            shifted["arr_time_id"] = offsetDate(arrID)
            shifted["dep_time_eff"] = offsetDate(depID)
            shifted["arr_time_eff"] = offsetDate(arrID)
            shifted["ref_time"] = offsetDate(ref)
            return shifted
        }
        return result
    }

    private static func matchesDepartureDay(
        info: [String: Any],
        departureDay: Date,
        fromStation: String,
        calendar: Calendar
    ) -> Bool {
        let stops = info["stops"] as? [[String: Any]] ?? []
        guard let stop = stops.first(where: { stationsMatch($0["name"] as? String, fromStation) }),
              let depTime = stop["dep_time_id"] as? Date ?? stop["dep_time_eff"] as? Date else {
            return false
        }
        return calendar.isDate(depTime, inSameDayAs: departureDay)
    }

    private static func trainContainsSegmentFuzzy(info: [String: Any], from: String, to: String) -> Bool {
        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.compactMap { $0["name"] as? String }
        guard let fromIdx = names.firstIndex(where: { stationsMatch($0, from) }),
              let toIdx = names.firstIndex(where: { stationsMatch($0, to) }) else { return false }
        return fromIdx <= toIdx
    }

    private static func matchedStationNames(
        in info: [String: Any],
        from: String,
        to: String
    ) -> (from: String, to: String) {
        let names = (info["stops"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let resolvedFrom = names.first(where: { stationsMatch($0, from) }) ?? from
        let resolvedTo = names.first(where: { stationsMatch($0, to) }) ?? to
        return (resolvedFrom, resolvedTo)
    }

    private static func stationsMatch(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a == b || a.contains(b) || b.contains(a)
    }

    private static func trainNumbersMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.filter(\.isNumber)
        let b = rhs.filter(\.isNumber)
        return !a.isEmpty && a == b
    }
}
