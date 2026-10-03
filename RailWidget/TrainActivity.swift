import ActivityKit
import Foundation

// MARK: - Attributes

/// What a live journey tells the Lock Screen.
///
/// Kept deliberately small. Attributes and state share a budget of roughly four
/// kilobytes, so nothing is carried that the extension could look up for itself —
/// the operator's mark is an asset name, never image data, and only the handful of
/// stops that get drawn are sent.
///
/// `nonisolated` because the app target defaults to the main actor, and ActivityKit
/// uses this conformance off it when an activity is requested or updated.
nonisolated struct TrainActivityAttributes: ActivityAttributes {

    // MARK: Static

    /// The asset name of the operator's mark, e.g. "FR", "ITALO".
    let logo: String
    let number: String

    /// The stations chosen when the journey was added: where boarding happens and
    /// where it ends. Neither is necessarily the train's own origin or terminus.
    let departureName: String
    let arrivalName: String

    /// Enough to open the journey from a tap.
    let trainID: UUID

    // MARK: Dynamic

    struct ContentState: Codable, Hashable {

        /// Which of the three rows the countdown is aimed at.
        enum TargetRole: String, Codable, Hashable {
            /// The train has not reached the boarding station yet.
            case departure
            /// It is running, and the next stop falls between boarding and alighting.
            case intermediate
            /// The next stop is the end of the journey.
            case arrival
        }

        /// One drawn line: a station, when the train is due there, and whether that
        /// time has moved.
        struct Row: Codable, Hashable {
            let name: String
            /// The delay-adjusted time.
            let effective: Date
            /// The booked time.
            let scheduled: Date
            let delay: Int
        }

        /// A passenger's coach and seat, and which ticket a tap opens.
        ///
        /// It lives here rather than in the attributes because the attributes are
        /// fixed the moment the activity starts. A passenger added afterwards — or a
        /// seat corrected — would never have reached the Lock Screen.
        struct Ticket: Codable, Hashable {
            /// "4 – 12A".
            let label: String
            /// Which seat's QR code a tap opens.
            let seatID: UUID
        }

        /// A stop the countdown can be aimed at: which one, when, and where to go.
        struct Target: Codable, Hashable {
            let name: String
            /// Delay-adjusted.
            let date: Date
            /// Empty when the operator has not said.
            let platform: String
            let role: TargetRole
        }

        /// The two rows drawn, and the only two. A stop in between is named by the
        /// countdown rather than given a line of its own.
        let departure: Row
        let arrival: Row

        /// The platform of the stop the countdown is aimed at, or empty when the
        /// operator has not said.
        var platform: String

        /// What the countdown is counting to, always delay-adjusted.
        var targetName: String
        var targetDate: Date
        var targetRole: TargetRole

        /// True once the train has left its own origin, which is what allows a
        /// middle row to appear at all.
        let hasDeparted: Bool

        let isCancelled: Bool

        /// The journey's end, so the lifecycle can tell when there is nothing left
        /// to show without re-reading the store.
        let journeyEnd: Date

        /// The first passenger who has a coach or a seat, or nil when nobody does.
        /// The mapping from a journey knows nothing of seats, so this is filled
        /// in afterwards.
        var ticket: Ticket? = nil

        /// Every stop after the one the countdown is aimed at, in running order, worked
        /// out from the times the app knew when it last ran. Nil when the countdown is
        /// already on the end of the journey.
        ///
        /// This is what lets the Lock Screen move on with the app closed. Nothing runs
        /// to update an activity then, but the view is drawn again when the system flips
        /// the activity to stale at `staleDate`, and whenever the screen wakes. Each
        /// time, `advanced(ifStale:)` drops every stop whose time has passed and draws
        /// the first one still ahead in the target's place.
        var upcoming: [Target]? = nil

        /// The stop straight after the target, or nil at the end of the journey.
        var following: Target? { upcoming?.first }

        /// Whether the platform shown is one to leave from rather than one the train
        /// is pulling into.
        ///
        /// It points up out of a platform only while the boarding station is still
        /// ahead, because that is the one platform the traveller walks onto. Once
        /// aboard, every stop the countdown names — one in the middle of the leg or
        /// the end of it — is somewhere the train arrives, so the arrow turns down
        /// into it.
        var isBoardingPlatform: Bool { targetRole == .departure }

        /// The state as it should be drawn.
        ///
        /// A stop whose time has passed is skipped, so a long run of stops is walked
        /// through in one go: the first one still ahead takes the target's place — its
        /// name, its platform, its time and the arrow that goes with its role — and the
        /// activity is drawn as live again, counting to it. With nothing left ahead,
        /// this is the end of the journey and stays stale, which reads "Now".
        func advanced(
            ifStale isStale: Bool,
            now: Date = Date()
        ) -> (state: ContentState, isStale: Bool) {
            var passed = isStale || targetDate <= now
            guard passed, var rest = upcoming, !rest.isEmpty else { return (self, isStale) }

            var moved = self
            while passed, !rest.isEmpty {
                let next = rest.removeFirst()
                moved.targetName = next.name
                moved.targetDate = next.date
                moved.platform = next.platform
                moved.targetRole = next.role
                passed = next.date <= now
            }
            moved.upcoming = rest.isEmpty ? nil : rest
            return (moved, passed)
        }
    }
}

// MARK: - Input

/// A journey reduced to plain values.
///
/// The mapping below is the one piece of this feature with real rules in it, so it
/// is kept clear of SwiftData: it can be exercised with literals rather than a model
/// container.
struct TrainJourney: Equatable {

    /// One station the train calls at. Named for the act rather than the place, so
    /// it cannot be confused with the stored `Stop` it is built from.
    struct Call: Equatable {
        let name: String
        let platform: String

        /// True for exactly the run of stops from the boarding station to the
        /// alighting one, inclusive. This is how the app has always recorded the
        /// chosen leg of a longer service.
        let isSelected: Bool

        /// The operator has struck this stop from the run; the train passes without
        /// calling.
        let isCancelled: Bool

        /// The train is known to have called here already.
        let isCompleted: Bool

        let refTime: Date
        let departureScheduled: Date
        let departureEffective: Date
        let arrivalScheduled: Date
        let arrivalEffective: Date
        let departureDelay: Int
        let arrivalDelay: Int
    }

    let logo: String
    let number: String
    let isCancelled: Bool
    /// Every station of the run, in running order.
    let calls: [Call]
}

// MARK: - Mapping

enum TrainActivityState {

    /// Turns a journey into what the Live Activity should be showing right now.
    ///
    /// Returns nil when there is nothing to show: no chosen leg, or a journey whose
    /// end has already passed.
    ///
    /// The rules, in one place:
    ///
    /// - D is the first chosen stop and A the last. Those two are the only rows.
    /// - The countdown is aimed at D until the train has called there, and at the
    ///   next uncalled stop afterwards.
    /// - A stop between D and A is never given a row; it is named by the countdown,
    ///   which is where "approaching Alessandria" belongs anyway.
    /// - Every time used is the delay-adjusted one.
    static func resolve(_ journey: TrainJourney, now: Date = Date()) -> TrainActivityAttributes.ContentState? {
        guard var state = resolveTarget(journey, now: now) else { return nil }

        // The same rules asked a second after each target, when it will have been
        // reached: whatever they aim at then is the stop after it. Anything that is not
        // strictly later is the end of the journey, and there is nothing after that.
        // Bounded, because every stop sent counts against the activity's size budget.
        var chain: [TrainActivityAttributes.ContentState.Target] = []
        var cursor = state.targetDate
        while chain.count < 12,
              let later = resolveTarget(journey, now: cursor.addingTimeInterval(1)),
              later.targetDate > cursor {
            chain.append(.init(
                name: later.targetName,
                date: later.targetDate,
                platform: later.platform,
                role: later.targetRole
            ))
            cursor = later.targetDate
        }
        state.upcoming = chain.isEmpty ? nil : chain

        return state
    }

    /// One reading of the rules, without looking past it.
    private static func resolveTarget(_ journey: TrainJourney, now: Date) -> TrainActivityAttributes.ContentState? {
        let route = journey.calls.sorted { $0.refTime < $1.refTime }
        let chosen = route.filter(\.isSelected)
        guard let boarding = chosen.first, let alighting = chosen.last else { return nil }

        let journeyEnd = arrivalMoment(of: alighting) ?? departureMoment(of: alighting) ?? .distantPast
        guard journeyEnd > .distantPast else { return nil }

        let hasDeparted = hasLeftOrigin(route: route, now: now, isCancelled: journey.isCancelled)

        // The next stop the train has yet to call at, over the whole run. Because the
        // chosen stops are a contiguous run, anything between D and A is chosen too,
        // so this needs no second search.
        let next = route.first { !hasCalled(at: $0, now: now, hasDeparted: hasDeparted) && !$0.isCancelled }

        let reachedBoarding = hasCalled(at: boarding, now: now, hasDeparted: hasDeparted)

        // Aimed at the boarding station until the train has been there. A train that
        // starts where you board is counted to its departure; one that merely passes
        // through, to its arrival.
        let target: (stop: TrainJourney.Call, date: Date, role: TrainActivityAttributes.ContentState.TargetRole)
        if !reachedBoarding {
            let startsHere = boarding.name == route.first?.name
            let date = (startsHere ? departureMoment(of: boarding) : arrivalMoment(of: boarding))
                ?? departureMoment(of: boarding)
                ?? arrivalMoment(of: boarding)
                ?? journeyEnd
            target = (boarding, date, .departure)
        } else if let next, next.name != alighting.name, isStrictlyBetween(next, boarding, alighting, in: route) {
            target = (next, arrivalMoment(of: next) ?? journeyEnd, .intermediate)
        } else {
            target = (alighting, journeyEnd, .arrival)
        }

        return TrainActivityAttributes.ContentState(
            departure: row(for: boarding, using: .departure),
            arrival: row(for: alighting, using: .arrival),
            platform: target.stop.platform,
            targetName: target.stop.name,
            targetDate: target.date,
            targetRole: target.role,
            hasDeparted: hasDeparted,
            isCancelled: journey.isCancelled,
            journeyEnd: journeyEnd
        )
    }

    // MARK: Helpers

    private enum Side { case departure, arrival }

    private static func row(
        for stop: TrainJourney.Call,
        using side: Side
    ) -> TrainActivityAttributes.ContentState.Row {
        switch side {
        case .departure:
            return .init(
                name: stop.name,
                effective: departureMoment(of: stop) ?? arrivalMoment(of: stop) ?? .distantPast,
                scheduled: usable(stop.departureScheduled) ?? usable(stop.arrivalScheduled) ?? .distantPast,
                delay: stop.departureDelay
            )
        case .arrival:
            return .init(
                name: stop.name,
                effective: arrivalMoment(of: stop) ?? departureMoment(of: stop) ?? .distantPast,
                scheduled: usable(stop.arrivalScheduled) ?? usable(stop.departureScheduled) ?? .distantPast,
                delay: stop.arrivalDelay
            )
        }
    }

    /// Strictly between the two ends of the chosen leg, judged by position on the
    /// run rather than by name, so a service that calls at a station twice is read
    /// correctly.
    private static func isStrictlyBetween(
        _ stop: TrainJourney.Call,
        _ boarding: TrainJourney.Call,
        _ alighting: TrainJourney.Call,
        in route: [TrainJourney.Call]
    ) -> Bool {
        guard let index = route.firstIndex(of: stop),
              let start = route.firstIndex(of: boarding),
              let end = route.firstIndex(of: alighting) else { return false }
        return index > start && index < end
    }

    /// Whether the train has already called at a stop.
    ///
    /// The operator's own word comes first; the clock only stands in for it, and only
    /// once the train is actually running. Without that second condition a journey
    /// later today would read as half-completed the moment it was looked at.
    private static func hasCalled(at stop: TrainJourney.Call, now: Date, hasDeparted: Bool) -> Bool {
        if stop.isCompleted { return true }
        guard hasDeparted else { return false }
        // A train that has pulled out has certainly called. Without this an origin, which
        // has a departure and no arrival, was never counted as called by the clock alone.
        if let departure = departureMoment(of: stop), now >= departure { return true }
        guard let arrival = arrivalMoment(of: stop) else { return false }
        return now >= arrival
    }

    /// True once the train has left the first stop of its run — not of the chosen leg.
    private static func hasLeftOrigin(route: [TrainJourney.Call], now: Date, isCancelled: Bool) -> Bool {
        guard !isCancelled, let origin = route.first else { return false }
        if origin.isCompleted, !origin.isCancelled { return true }
        guard let departure = departureMoment(of: origin) else { return false }
        return now >= departure
    }

    private static func arrivalMoment(of stop: TrainJourney.Call) -> Date? {
        usable(stop.arrivalEffective) ?? usable(stop.arrivalScheduled)
    }

    private static func departureMoment(of stop: TrainJourney.Call) -> Date? {
        usable(stop.departureEffective) ?? usable(stop.departureScheduled)
    }

    /// The feeds use several values to mean "no time here", including the Unix epoch
    /// where a terminus has no departure or an origin no arrival.
    private static func usable(_ date: Date) -> Date? {
        guard date != .distantPast, date != .distantFuture,
              date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}

// MARK: - Scheduling

/// When a live journey should begin, and when one that has run too long should be
/// started over.
///
/// Pure arithmetic, kept apart from ActivityKit so the rules can be read and tested
/// without a device.
enum TrainActivitySchedule {

    /// A journey goes live an hour before boarding.
    static let lead: TimeInterval = 60 * 60

    /// The system ends a Live Activity eight hours after it actually starts, and
    /// neither an update nor opening the app resets that. Everything below aims to
    /// stay an hour clear of it.
    static let systemCap: TimeInterval = 8 * 60 * 60
    static let safeSpan: TimeInterval = 7 * 60 * 60

    /// When to ask the system to start the activity.
    ///
    /// An hour before boarding, unless that would spend the eight-hour allowance
    /// before the journey ends — a long run is started later so it is still alive on
    /// arrival. Never earlier than now, since a start in the past is meaningless.
    ///
    /// - Returns: nil when boarding has already happened, which means there is
    ///   nothing to schedule and the caller should start one immediately instead.
    static func start(boarding: Date, journeyEnd: Date, now: Date = Date()) -> Date? {
        guard boarding > now else { return nil }

        let preferred = boarding.addingTimeInterval(-lead)
        let latestUseful = journeyEnd.addingTimeInterval(-safeSpan)
        return max(max(preferred, latestUseful), now)
    }

    /// Whether the activity should be started now rather than scheduled, because
    /// boarding is already inside the hour.
    static func shouldStartImmediately(boarding: Date, now: Date = Date()) -> Bool {
        boarding.addingTimeInterval(-lead) <= now
    }

    /// Whether a running activity is close enough to the eight-hour wall to be worth
    /// replacing with a fresh one.
    ///
    /// Only ever true while there is still journey left to show: replacing an
    /// activity for a journey that is over would just put it back on the screen.
    static func shouldRestart(startedAt: Date, journeyEnd: Date, now: Date = Date()) -> Bool {
        guard journeyEnd > now else { return false }
        return now.timeIntervalSince(startedAt) >= safeSpan
    }

    /// Whether there is anything left to show.
    static func isOver(journeyEnd: Date, now: Date = Date()) -> Bool {
        now >= journeyEnd
    }
}

// MARK: - Deep links

/// Where a tap goes. Both forms are ones the app already answers.
enum TrainActivityLinks {
    /// Marks a link as having come from the Live Activity itself, rather than a
    /// notification or a station board — the one case where the details screen
    /// should jump ahead to the next station instead of opening on the first.
    static let liveActivitySource = "liveActivity"

    static func journey(_ attributes: TrainActivityAttributes) -> URL? {
        URL(string: "railapp://view-train?trainID=\(attributes.trainID.uuidString)&source=\(liveActivitySource)")
    }

    /// The journey *and* the seat's ticket, opened straight to its QR code.
    static func seat(
        _ attributes: TrainActivityAttributes,
        _ ticket: TrainActivityAttributes.ContentState.Ticket
    ) -> URL? {
        URL(
            string: "railapp://view-ticket?trainID=\(attributes.trainID.uuidString)&seatID=\(ticket.seatID.uuidString)&source=\(liveActivitySource)"
        )
    }
}

// MARK: - Samples

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

    /// Boarding is minutes away, so the countdown is at its shortest ("3:59").
    static let imminent = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: 4),
        Leg(name: "Milano Centrale", platform: "14", minutes: 60),
        Leg(name: "Roma Termini", platform: "1", minutes: 250)
    ])

    /// Running, with the next stop over two hours off, so the countdown is at its
    /// longest ("129:59") and the timer's slot at its widest.
    static let longLeg = journey([
        Leg(name: "Torino Porta Nuova", platform: "3", minutes: -90, isCompleted: true),
        Leg(name: "Bologna Centrale", platform: "17", minutes: 130),
        Leg(name: "Roma Termini", platform: "1", minutes: 260)
    ])

    /// A platform that is more than a number, which is how some stations write them.
    static let widePlatform = journey([
        Leg(name: "Torino Porta Nuova", platform: "12 Ovest", minutes: 30),
        Leg(name: "Roma Termini", platform: "1", minutes: 250)
    ])

    /// Names long enough to test the truncation on every row.
    static let longNames = journey(logo: "ITALO", number: "9924", [
        Leg(name: "Reggio Emilia AV Mediopadana", platform: "13", minutes: -40, isCompleted: true),
        Leg(name: "Bolzano Bozen Hauptbahnhof", platform: "4", minutes: 35),
        Leg(name: "Villa San Giovanni Marittima", platform: "2", minutes: 150)
    ])

    // MARK: - States

    static func state(
        _ journey: TrainJourney,
        ticket: TrainActivityAttributes.ContentState.Ticket? = nil,
        now: Date = reference
    ) -> TrainActivityAttributes.ContentState {
        var state = TrainActivityState.resolve(journey, now: now)!
        state.ticket = ticket
        return state
    }

    // MARK: - Attributes

    static let attributes = TrainActivityAttributes(
        logo: "FR",
        number: "9612",
        departureName: "Torino Porta Nuova",
        arrivalName: "Roma Termini",
        trainID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )

    /// The same journey with a different operator's mark, to see one that is not
    /// Trenitalia's.
    static let italo = TrainActivityAttributes(
        logo: "ITALO",
        number: "9924",
        departureName: "Torino Porta Nuova",
        arrivalName: "Roma Termini",
        trainID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    )

    // MARK: - Tickets

    /// A passenger with a coach and a seat.
    static let ticket = TrainActivityAttributes.ContentState.Ticket(
        label: "4 – 12A",
        seatID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    )
}
#endif
