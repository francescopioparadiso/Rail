import ActivityKit
import Foundation

// MARK: - Attributes

/// What a live journey tells the Lock Screen.
///
/// Kept deliberately small. Attributes and state share a budget of roughly four
/// kilobytes, so nothing is carried that the extension could look up for itself —
/// the operator's mark is an asset name, never image data, and only the handful of
/// stops that get drawn are sent.
struct TrainActivityAttributes: ActivityAttributes {

    // MARK: Static

    /// The asset name of the operator's mark, e.g. "FR", "ITALO".
    let logo: String
    let number: String

    /// The stations chosen when the journey was added: where boarding happens and
    /// where it ends. Neither is necessarily the train's own origin or terminus.
    let departureName: String
    let arrivalName: String

    /// "4 · 12A" for the first passenger, or empty when nobody has entered a seat.
    let seatLabel: String

    /// Enough to open the journey, and the seat's QR code, from a tap.
    let trainID: UUID
    let seatID: UUID?

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

        /// The two rows drawn, and the only two. A stop in between is named by the
        /// countdown rather than given a line of its own.
        let departure: Row
        let arrival: Row

        /// The platform of the stop the countdown is aimed at, or empty when the
        /// operator has not said.
        let platform: String

        /// What the countdown is counting to, always delay-adjusted.
        let targetName: String
        let targetDate: Date
        let targetRole: TargetRole

        /// True once the train has left its own origin, which is what allows a
        /// middle row to appear at all.
        let hasDeparted: Bool

        let isCancelled: Bool

        /// The journey's end, so the lifecycle can tell when there is nothing left
        /// to show without re-reading the store.
        let journeyEnd: Date
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
        guard hasDeparted, let arrival = arrivalMoment(of: stop) else { return false }
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
