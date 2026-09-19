import Foundation

#if DEBUG

/// Journeys to draw and to test against.
///
/// They are built as whole runs and put through `TrainActivityState.resolve`, rather
/// than written out as finished content. A preview that made its own state could
/// show a middle row the real rules would never produce; these cannot.
enum TrainActivitySample {

    /// A station on a made-up run.
    struct Leg {
        let name: String
        let platform: String
        /// Minutes from the reference moment. Negative is in the past.
        let minutes: Int
        var delay: Int = 0
        var isSelected: Bool = true
        var isCompleted: Bool = false
        var isCancelled: Bool = false
    }

    /// Taken once, so every sample and every assertion in a run agrees on "now"
    /// while the previews still draw against the real clock — a fixed date in the
    /// past would leave every one of them stale.
    static let reference = Date()

    static func journey(
        logo: String = "FR",
        number: String = "9612",
        isCancelled: Bool = false,
        _ legs: [Leg],
        from origin: Date = reference
    ) -> TrainJourney {
        TrainJourney(
            logo: logo,
            number: number,
            isCancelled: isCancelled,
            calls: legs.map { leg in
                let scheduled = origin.addingTimeInterval(TimeInterval(leg.minutes * 60))
                let effective = scheduled.addingTimeInterval(TimeInterval(leg.delay * 60))
                return TrainJourney.Call(
                    name: leg.name,
                    platform: leg.platform,
                    isSelected: leg.isSelected,
                    isCancelled: leg.isCancelled,
                    isCompleted: leg.isCompleted,
                    refTime: scheduled,
                    departureScheduled: scheduled,
                    departureEffective: effective,
                    arrivalScheduled: scheduled,
                    arrivalEffective: effective,
                    departureDelay: leg.delay,
                    arrivalDelay: leg.delay
                )
            }
        )
    }

    // MARK: - Journeys

    /// Boarding is an hour off and the train has not left its origin. Two rows, the
    /// boarding station blue.
    static let notDeparted = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: 60),
        Leg(name: "Milano Centrale", platform: "14", minutes: 120),
        Leg(name: "Bologna Centrale", platform: "17", minutes: 200),
        Leg(name: "Roma Termini", platform: "1", minutes: 320)
    ])

    /// Running, with a stop still to come between boarding and alighting. Three rows.
    static let enRoute = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -90, isCompleted: true),
        Leg(name: "Milano Centrale", platform: "14", minutes: -30, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: 45),
        Leg(name: "Roma Termini", platform: "1", minutes: 160)
    ])

    /// The last intermediate stop is behind it, so the countdown is on the end of the
    /// journey and the middle row is gone.
    static let nextIsArrival = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -180, isCompleted: true),
        Leg(name: "Milano Centrale", platform: "14", minutes: -120, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: -40, isCompleted: true),
        Leg(name: "Roma Termini", platform: "1", minutes: 25)
    ])

    /// The countdown has run out: the target is behind us, so the activity is stale
    /// and the capsule reads "Now".
    static let arrivingNow = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -200, isCompleted: true),
        Leg(name: "Milano Centrale", platform: "14", minutes: -140, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: -60, isCompleted: true),
        Leg(name: "Roma Termini", platform: "1", minutes: -1)
    ])

    /// Twelve minutes down, which is the case where the times shown stop being the
    /// timetable's.
    static let delayed = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -90, delay: 12, isCompleted: true),
        Leg(name: "Milano Centrale", platform: "14", minutes: -30, delay: 12, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: 45, delay: 12),
        Leg(name: "Roma Termini", platform: "1", minutes: 160, delay: 12)
    ])

    /// The operator has not said which platform yet, so there is no yellow chip.
    static let noPlatform = journey([
        Leg(name: "Torino Porta Nuova", platform: "-", minutes: 60),
        Leg(name: "Milano Centrale", platform: "-", minutes: 120),
        Leg(name: "Roma Termini", platform: "", minutes: 320)
    ])

    /// A leg in the middle of a longer service: boarding and alighting are neither
    /// the origin nor the terminus.
    static let midRoute = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -120, isSelected: false, isCompleted: true),
        Leg(name: "Milano Centrale", platform: "14", minutes: -20, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: 50),
        Leg(name: "Firenze S.M.N.", platform: "9", minutes: 95),
        Leg(name: "Roma Termini", platform: "1", minutes: 160, isSelected: false)
    ])

    /// Names long enough to test the truncation on every row.
    static let longNames = journey(logo: "ITALO", number: "9924", [
        Leg(name: "Reggio Emilia AV Mediopadana", platform: "13", minutes: -40, isCompleted: true),
        Leg(name: "Bolzano Bozen Hauptbahnhof", platform: "4", minutes: 35),
        Leg(name: "Villa San Giovanni Marittima", platform: "2", minutes: 150)
    ])

    // MARK: - States

    static func state(_ journey: TrainJourney, now: Date = reference) -> TrainActivityAttributes.ContentState {
        TrainActivityState.resolve(journey, now: now)!
    }

    // MARK: - Attributes

    static let withSeat = TrainActivityAttributes(
        logo: "FR",
        number: "9612",
        departureName: "Torino Porta Nuova",
        arrivalName: "Roma Termini",
        seatLabel: "4 · 12A",
        trainID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        seatID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    )

    /// Nobody has entered a seat, so the capsule is absent rather than empty.
    static let withoutSeat = TrainActivityAttributes(
        logo: "ITALO",
        number: "9924",
        departureName: "Torino Porta Nuova",
        arrivalName: "Roma Termini",
        seatLabel: "",
        trainID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        seatID: nil
    )

    /// Several passengers are travelling; the first is the one shown.
    static let manyPassengers = TrainActivityAttributes(
        logo: "FR",
        number: "9612",
        departureName: "Torino Porta Nuova",
        arrivalName: "Roma Termini",
        seatLabel: "7 · 3C",
        trainID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        seatID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    )
}

#endif
