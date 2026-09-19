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
    init(train: Train, stops: [Stop], seats: [Seat]) {
        let chosen = stops.filter(\.is_selected).sorted { $0.ref_time < $1.ref_time }

        // Whoever is listed first, matching the ticket widget's idea of "the" seat.
        // A journey with several passengers shows one; the rest are a tap away.
        let seat = seats.first

        let label: String = {
            guard let seat else { return "" }
            let carriage = seat.carriage.trimmingCharacters(in: .whitespaces)
            let number = seat.number.trimmingCharacters(in: .whitespaces)
            guard !carriage.isEmpty || !number.isEmpty else { return "" }
            guard !carriage.isEmpty else { return number }
            guard !number.isEmpty else { return carriage }
            return "\(carriage) · \(number)"
        }()

        self.init(
            logo: train.logo,
            number: train.number,
            departureName: chosen.first?.name ?? "",
            arrivalName: chosen.last?.name ?? "",
            seatLabel: label,
            trainID: train.id,
            seatID: seat?.id
        )
    }
}
