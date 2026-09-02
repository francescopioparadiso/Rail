import Foundation

struct ConnectionRowItem {
    let durationString: String
    let totalMinutes: Int
    let connectionStatus: ConnectionStatus
    let station: String
    let weather: String
    let index: Int
    let total: Int
}

struct TrainRowItem: Identifiable {
    let id: UUID
    let train: Train
    let trainStops: [Stop]
    let summary: StopSummary
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let connection: ConnectionRowItem?
}

enum TrainListBuilder {
    static func todayItems(trains: [Train], stops: [Stop], now: Date = Date()) -> [TrainRowItem] {
        let calendar = Calendar.current
        let stopsByTrain = Dictionary(grouping: stops, by: \.id)

        let todayTrains = trains
            .filter { train in
                guard let trainStops = stopsByTrain[train.id] else { return false }
                let selectedStops = trainStops.filter(\.is_selected)
                guard let lastStop = selectedStops.max(by: { $0.ref_time < $1.ref_time }) else { return false }
                return now <= lastStop.arr_time_eff || calendar.isDateInToday(lastStop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                let lhsFirst = (stopsByTrain[lhs.id] ?? []).filter(\.is_selected).min(by: { $0.ref_time < $1.ref_time })
                let rhsFirst = (stopsByTrain[rhs.id] ?? []).filter(\.is_selected).min(by: { $0.ref_time < $1.ref_time })
                guard let lTime = lhsFirst?.dep_time_eff, let rTime = rhsFirst?.dep_time_eff else { return false }
                return lTime < rTime
            }

        let totalConnections = todayTrains.indices.dropLast().reduce(0) { count, i in
            hasInterval(trains: todayTrains, from: i, to: i + 1, stopsByTrain: stopsByTrain) ? count + 1 : count
        }

        var connectionCounter = 0

        return todayTrains.enumerated().map { index, train in
            let trainStops = (stopsByTrain[train.id] ?? []).sorted(by: { $0.ref_time < $1.ref_time })
            let summary = StopSummary.calculate(in: trainStops)

            let hasIntervalBefore = hasInterval(trains: todayTrains, from: index - 1, to: index, stopsByTrain: stopsByTrain)
            let hasIntervalAfter = hasInterval(trains: todayTrains, from: index, to: index + 1, stopsByTrain: stopsByTrain)

            let connection: ConnectionRowItem? = {
                guard hasIntervalAfter, index + 1 < todayTrains.count else { return nil }
                let nextTrain = todayTrains[index + 1]
                let currentArrDate = summary.last.arr_time_eff
                let nextDepDate = (stopsByTrain[nextTrain.id] ?? [])
                    .filter(\.is_selected)
                    .min(by: { $0.ref_time < $1.ref_time })?
                    .dep_time_eff ?? .distantPast

                let interval = nextDepDate.timeIntervalSince(currentArrDate)
                guard interval > 0, interval <= 24 * 60 * 60 else { return nil }

                connectionCounter += 1
                let totalMinutes = Int(interval) / 60
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                let durationString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

                return ConnectionRowItem(
                    durationString: durationString,
                    totalMinutes: totalMinutes,
                    connectionStatus: ConnectionStatus(minutes: totalMinutes),
                    station: summary.last.name,
                    weather: summary.last.weather,
                    index: connectionCounter,
                    total: totalConnections
                )
            }()

            return TrainRowItem(
                id: train.id,
                train: train,
                trainStops: trainStops,
                summary: summary,
                topPadding: hasIntervalBefore ? 2 : 6,
                bottomPadding: hasIntervalAfter ? 2 : 6,
                connection: connection
            )
        }
    }

    static func pastItems(trains: [Train], stops: [Stop], now: Date = Date()) -> [TrainRowItem] {
        let calendar = Calendar.current
        let stopsByTrain = Dictionary(grouping: stops, by: \.id)

        let pastTrains = trains
            .filter { train in
                guard let trainStops = stopsByTrain[train.id] else { return false }
                let sortedStops = trainStops.sorted(by: { $0.ref_time < $1.ref_time })
                guard let lastStop = sortedStops.last else { return false }
                return now > lastStop.arr_time_eff && !calendar.isDateInToday(lastStop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                let lhsLast = stopsByTrain[lhs.id]?.max(by: { $0.ref_time < $1.ref_time })
                let rhsLast = stopsByTrain[rhs.id]?.max(by: { $0.ref_time < $1.ref_time })
                guard let lTime = lhsLast?.arr_time_eff, let rTime = rhsLast?.arr_time_eff else { return false }
                return lTime > rTime
            }

        return pastTrains.enumerated().map { index, train in
            let trainStops = (stopsByTrain[train.id] ?? []).sorted(by: { $0.ref_time < $1.ref_time })
            return TrainRowItem(
                id: train.id,
                train: train,
                trainStops: trainStops,
                summary: StopSummary.calculate(in: trainStops),
                topPadding: 6,
                bottomPadding: 6,
                connection: nil
            )
        }
    }

    private static func hasInterval(
        trains: [Train],
        from sourceIndex: Int,
        to targetIndex: Int,
        stopsByTrain: [UUID: [Stop]]
    ) -> Bool {
        guard sourceIndex >= 0, sourceIndex < trains.count,
              targetIndex >= 0, targetIndex < trains.count else {
            return false
        }

        let sourceStops = (stopsByTrain[trains[sourceIndex].id] ?? [])
            .filter(\.is_selected)
            .sorted(by: { $0.ref_time < $1.ref_time })
        let targetStops = (stopsByTrain[trains[targetIndex].id] ?? [])
            .filter(\.is_selected)
            .sorted(by: { $0.ref_time < $1.ref_time })

        guard let sourceLastStop = sourceStops.last, let targetFirstStop = targetStops.first else { return false }
        return sourceLastStop.name == targetFirstStop.name && sourceLastStop.arr_time_eff < targetFirstStop.dep_time_eff
    }

    static func matches(_ item: TrainRowItem, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableFields = [
            item.train.number,
            item.train.identifier,
            item.train.direction,
            item.summary.first.name,
            item.summary.last.name,
            formattedSearchDate(item.summary.first.dep_time_eff),
            formattedSearchDate(item.summary.first.dep_time_id),
            formattedSearchDate(item.summary.last.arr_time_eff),
            formattedSearchDate(item.summary.last.arr_time_id)
        ]

        return searchableFields.contains { $0.lowercased().contains(query) }
    }

    private static func formattedSearchDate(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        let abbreviated = date.formatted(date: .abbreviated, time: .shortened)
        let detailed = date.formatted(.dateTime.day().month().year().hour().minute())
        let timeOnly = date.formatted(date: .omitted, time: .shortened)
        return "\(abbreviated) \(detailed) \(timeOnly)"
    }
}
