import Foundation

/// Carries a journey forward using only the times already stored on its stops.
///
/// Stop status normally arrives from the operator's API, so a train running while
/// the phone is offline stops progressing entirely: a station the train reached ten
/// minutes ago still reads "10m to arrival" and never turns complete, and the whole
/// list is frozen at the moment the connection dropped.
///
/// Between refreshes the clock is enough to keep moving, because the last known
/// effective times already say when the train is due at each stop. That is a
/// prediction, not an observation, so it only ever moves a stop forward — never
/// back — and the API stays authoritative: the next refresh that succeeds
/// overwrites whatever was inferred here with what actually happened.
@MainActor
enum TrainProgress {

    // MARK: - Methods

    /// Marks the stops this train is due to have reached by `now`.
    ///
    /// - Returns: whether anything changed, so callers can skip a needless save.
    @discardableResult
    static func advance(train: Train, stops: [Stop], now: Date = Date()) -> Bool {
        // A cancelled train isn't going anywhere; leave its stops as the API left them.
        guard train.issue != "Treno cancellato" else { return false }

        var changed = false
        for stop in stops {
            // Skip cancelled stops: the train passes them without calling.
            guard stop.status != 3 else { continue }

            if !stop.is_completed, let arrival = arrivalMoment(of: stop), now >= arrival {
                stop.is_completed = true
                changed = true
            }

            // Once the booked departure has passed the train can no longer be
            // standing there, so the row stops reading "At the station".
            if stop.is_in_station, let departure = departureMoment(of: stop), now >= departure {
                stop.is_in_station = false
                changed = true
            }
        }
        return changed
    }

    // MARK: - Helpers

    /// When the train is due at this stop. Origins often carry no arrival, so the
    /// departure stands in for them.
    private static func arrivalMoment(of stop: Stop) -> Date? {
        usable(stop.arr_time_eff) ?? usable(stop.arr_time_id)
            ?? usable(stop.dep_time_eff) ?? usable(stop.dep_time_id)
    }

    /// When the train is due to leave. A terminus has no departure, so nothing is
    /// inferred there and the stop simply stays complete.
    private static func departureMoment(of stop: Stop) -> Date? {
        usable(stop.dep_time_eff) ?? usable(stop.dep_time_id)
    }

    /// Feeds use the distant past and future as "no value"; neither is a real time.
    private static func usable(_ date: Date) -> Date? {
        date == .distantPast || date == .distantFuture ? nil : date
    }
}
