import Foundation

/// Turns what is in the store into the plain values the Live Activity is mapped from.
///
/// The one place that knows both sides, so `TrainActivityState.resolve` never has to
/// meet a SwiftData model.
extension TrainJourney {
    @MainActor
    init(train: Train, stops: [Stop]) {
        self.init(
            logo: train.logo,
            number: train.number,
            isCancelled: train.issue == "Treno cancellato",
            calls: stops
                .sorted { $0.ref_time < $1.ref_time }
                .map { stop in
                    Call(
                        name: stop.name,
                        platform: stop.platform,
                        isSelected: stop.is_selected,
                        // 3 is the operator's code for a stop struck from the run.
                        isCancelled: stop.status == 3,
                        isCompleted: stop.is_completed,
                        refTime: stop.ref_time,
                        departureScheduled: stop.dep_time_id,
                        departureEffective: stop.dep_time_eff,
                        arrivalScheduled: stop.arr_time_id,
                        arrivalEffective: stop.arr_time_eff,
                        departureDelay: stop.dep_delay,
                        arrivalDelay: stop.arr_delay
                    )
                }
        )
    }
}

extension TrainActivityAttributes {
    /// The unchanging half of a live journey: what it is, and what a tap on it opens.
    @MainActor
    init(train: Train, stops: [Stop]) {
        let chosen = stops.filter(\.is_selected).sorted { $0.ref_time < $1.ref_time }

        self.init(
            logo: train.logo,
            number: train.number,
            departureName: chosen.first?.name ?? "",
            arrivalName: chosen.last?.name ?? "",
            trainID: train.id
        )
    }
}

extension TrainActivityAttributes.ContentState.Ticket {
    /// The seat a live journey shows, if there is one worth showing.
    ///
    /// Whoever is listed first among the passengers who have a coach or a seat is the
    /// one shown; a journey with several passengers shows one, and the rest are a
    /// tap away.
    ///
    /// The QR code is not asked for. The form saves a seat with or without one, and
    /// requiring it meant a passenger who had been entered never appeared. The tap
    /// opens the ticket either way.
    @MainActor
    init?(seats: [Seat]) {
        for seat in seats {
            let carriage = seat.carriage.trimmingCharacters(in: .whitespaces)
            let number = seat.number.trimmingCharacters(in: .whitespaces)
            let label = [carriage, number].filter { !$0.isEmpty }.joined(separator: " – ")
            guard !label.isEmpty else { continue }

            self.init(label: label, seatID: seat.id)
            return
        }
        return nil
    }
}
