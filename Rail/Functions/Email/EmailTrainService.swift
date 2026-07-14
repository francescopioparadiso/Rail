import Foundation
import SwiftData
import WidgetKit

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
        let results = await fetch_common_train_list(number: ticket.trainNumber)

        let matching = results.filter {
            FavoriteTrainService.trainContainsSegment(info: $0, from: fromStation, to: toStation)
        }

        if let best = matching.first(where: { matchesDepartureDay(info: $0, departureDay: departureDay, fromStation: fromStation) }) ?? matching.first {
            return PreparedEmailTrain(
                prepared: PreparedFavoriteTrain(info: best, fromStation: fromStation, toStation: toStation),
                passengers: ticket.passengers
            )
        }

        let departureSuggestions = await TrenitaliaAPI().station_autocomplete(name: fromStation)
        let arrivalSuggestions = await TrenitaliaAPI().station_autocomplete(name: toStation)
        guard let departureCode = departureSuggestions.first?.code,
              let arrivalCode = arrivalSuggestions.first?.code else { return nil }

        let solutions = await TrenitaliaAPI().train_solutions(
            departureLocationId: departureCode,
            arrivalLocationId: arrivalCode,
            departureTime: departureDay
        )

        let bestSegment = solutions
            .flatMap(\.segments)
            .filter { $0.origin == fromStation && $0.destination == toStation }
            .min(by: {
                abs($0.departureTime.timeIntervalSince(departureDay)) <
                abs($1.departureTime.timeIntervalSince(departureDay))
            })

        if let segment = bestSegment {
            let identifiers = await TrenitaliaAPI().train_list(number: segment.number, code: segment.stationCode)
            let segmentDay = Calendar.current.startOfDay(for: segment.departureTime)

            let targetIdentifier = identifiers.first(where: { id in
                guard let tsString = id.split(separator: "/").last, let ms = Double(tsString) else { return false }
                return Calendar.current.isDate(Date(timeIntervalSince1970: ms / 1000), inSameDayAs: segmentDay)
            }) ?? identifiers.first

            if let identifier = targetIdentifier,
               let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: true),
               FavoriteTrainService.trainContainsSegment(info: info, from: fromStation, to: toStation) {
                return PreparedEmailTrain(
                    prepared: PreparedFavoriteTrain(info: info, fromStation: fromStation, toStation: toStation),
                    passengers: ticket.passengers
                )
            }
        }

        return nil
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

        var addedSeats: [Seat] = []
        for passenger in emailTrain.passengers {
            let seat = Seat(
                id: UUID(),
                trainID: id,
                name: passenger.name,
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

        reload_widget_timelines()
    }

    private static func matchesDepartureDay(info: [String: Any], departureDay: Date, fromStation: String) -> Bool {
        let stops = info["stops"] as? [[String: Any]] ?? []
        guard let stop = stops.first(where: { ($0["name"] as? String) == fromStation }),
              let depTime = stop["dep_time_id"] as? Date ?? stop["dep_time_eff"] as? Date else {
            return false
        }
        return Calendar.current.isDate(depTime, inSameDayAs: departureDay)
    }
}
