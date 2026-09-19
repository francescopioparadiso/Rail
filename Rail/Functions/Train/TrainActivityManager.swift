import ActivityKit
import Foundation
import os

/// Keeps the Lock Screen's live journeys in step with what is in the store.
///
/// Everything runs on the device. There is no server and no push token: an activity
/// is asked for while the app is in front, the system starts it an hour before
/// boarding whether or not Rail is running, and it is brought up to date whenever
/// the app next gets a moment.
///
/// KNOWN LIMITATION — with the app closed, nothing recomputes which stop is next.
/// The countdown runs down to whatever stop was current when Rail last ran, flips to
/// "Now" there, and stays until the app runs again. Carrying it forward would need
/// background execution or a server, and this app has neither by design.
@MainActor
final class TrainActivityManager {

    // MARK: - Properties

    static let shared = TrainActivityManager()

    private static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "LiveActivity")

    /// Scheduled activities count against the system's ceiling just as running ones
    /// do, so a day of connections does not get to book the whole allowance. Two
    /// covers the usual case: one leg running while the next waits its turn.
    private static let maximumConcurrent = 2

    /// The store lives in the App Group beside everything else this app shares.
    private let defaults = UserDefaults(suiteName: SharedSwiftData.appGroupID) ?? .standard
    private static let recordsKey = "liveActivityRecords"

    private var enablementTask: Task<Void, Never>?

    private init() {}

    // MARK: - Types

    /// What is remembered about an activity between launches.
    ///
    /// The id is kept rather than trusted to `Activity.activities`, because whether
    /// that collection lists a not-yet-started activity is not something this code
    /// is willing to assume.
    private struct Record: Codable, Equatable {
        let tripID: UUID
        let activityID: String
        /// When the system was asked to start it. For a scheduled activity this
        /// doubles as its age, which is what the eight-hour wall is measured from.
        let startDate: Date
        let journeyEnd: Date
    }

    // MARK: - Availability

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Watches for Live Activities being switched off in Settings, so the app stops
    /// asking for something it will only be refused.
    func observeEnablement() {
        guard enablementTask == nil else { return }
        enablementTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard let self else { return }
                Self.logger.info("Live Activities \(enabled ? "enabled" : "disabled", privacy: .public)")
                if !enabled { await self.endAll() }
            }
        }
    }

    // MARK: - Syncing

    /// Brings every live journey in line with the times now in the store.
    ///
    /// This is the same pass that reschedules the local alerts, and is called from
    /// the same places, so a delay that moves an alert moves the Lock Screen too.
    /// The local notification stays regardless: it is the fallback for a device
    /// where Live Activities are off or refused.
    func sync(trains: [Train], stops: [Stop], seats: [Seat], now: Date = Date()) async {
        guard areActivitiesEnabled else {
            await endAll()
            return
        }

        let stopsByTrain = Dictionary(grouping: stops, by: \.id)
        let seatsByTrain = Dictionary(grouping: seats, by: \.trainID)

        // Every journey still worth a place on the Lock Screen, soonest first.
        let candidates: [(train: Train, state: TrainActivityAttributes.ContentState, stops: [Stop])] =
            trains.compactMap { train in
                let trainStops = stopsByTrain[train.id] ?? []
                guard !trainStops.isEmpty else { return nil }
                let journey = TrainJourney(train: train, stops: trainStops)
                guard !journey.isCancelled,
                      let state = TrainActivityState.resolve(journey, now: now),
                      !TrainActivitySchedule.isOver(journeyEnd: state.journeyEnd, now: now)
                else { return nil }
                return (train, state, trainStops)
            }
            .sorted { $0.state.departure.effective < $1.state.departure.effective }
            .prefix(Self.maximumConcurrent)
            .map { $0 }

        let wanted = Set(candidates.map(\.train.id))

        // Anything remembered that is no longer wanted — arrived, deleted, cancelled,
        // or pushed out by a nearer journey — comes down first, freeing a slot.
        for record in records() where !wanted.contains(record.tripID) {
            await end(tripID: record.tripID)
        }

        for candidate in candidates {
            await apply(
                state: candidate.state,
                train: candidate.train,
                stops: candidate.stops,
                seats: seatsByTrain[candidate.train.id] ?? [],
                now: now
            )
        }
    }

    /// Starts, updates or replaces the one activity for a journey.
    private func apply(
        state: TrainActivityAttributes.ContentState,
        train: Train,
        stops: [Stop],
        seats: [Seat],
        now: Date
    ) async {
        let attributes = TrainActivityAttributes(train: train, stops: stops, seats: seats)
        let content = ActivityContent(state: state, staleDate: state.targetDate)

        if let record = record(for: train.id) {
            // Eight hours after it actually began the system takes the activity away
            // for good, and nothing this app does resets that clock. A long journey
            // is therefore torn down and asked for again while it still has a while
            // to run.
            if TrainActivitySchedule.shouldRestart(
                startedAt: record.startDate,
                journeyEnd: state.journeyEnd,
                now: now
            ) {
                Self.logger.info("Restarting a live journey that is near the eight-hour limit")
                await end(tripID: train.id)
                await request(attributes: attributes, content: content, start: nil, tripID: train.id, state: state, now: now)
                return
            }

            if await updateActivity(id: record.activityID, content: content) { return }

            // Either it is gone or it would not take the update. Rather than guess
            // which, take it down and ask again.
            Self.logger.info("Could not update the stored activity; replacing it")
            await end(tripID: train.id)
        }

        let boarding = state.departure.effective
        if TrainActivitySchedule.shouldStartImmediately(boarding: boarding, now: now) {
            await request(attributes: attributes, content: content, start: nil, tripID: train.id, state: state, now: now)
        } else if let start = TrainActivitySchedule.start(
            boarding: boarding,
            journeyEnd: state.journeyEnd,
            now: now
        ) {
            await request(attributes: attributes, content: content, start: start, tripID: train.id, state: state, now: now)
        }
    }

    // MARK: - ActivityKit

    /// The one place that touches a stored activity id.
    ///
    /// Two things here are not settled: whether `Activity.activities` lists an
    /// activity the system has not started yet, and whether such an activity will
    /// take an update at all. Both are treated as possible failures — a false return
    /// means "assume nothing, start over" — so the feature behaves correctly either
    /// way. Worth confirming on a device; if updates do reach a pending activity,
    /// this simply stops being the path that runs.
    private func updateActivity(id: String, content: ActivityContent<TrainActivityAttributes.ContentState>) async -> Bool {
        guard let activity = Activity<TrainActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return false
        }
        switch activity.activityState {
        case .ended, .dismissed:
            return false
        default:
            await activity.update(content)
            return true
        }
    }

    private func request(
        attributes: TrainActivityAttributes,
        content: ActivityContent<TrainActivityAttributes.ContentState>,
        start: Date?,
        tripID: UUID,
        state: TrainActivityAttributes.ContentState,
        now: Date
    ) async {
        do {
            // `start` is not optional on the scheduled form, so the immediate case is
            // a different call rather than a nil argument.
            let activity: Activity<TrainActivityAttributes>
            if let start {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: Self.alertConfiguration(for: attributes),
                    start: start
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard
                )
            }
            store(
                Record(
                    tripID: tripID,
                    activityID: activity.id,
                    startDate: start ?? now,
                    journeyEnd: state.journeyEnd
                )
            )
            Self.logger.info("Live journey \(start == nil ? "started" : "scheduled", privacy: .public) for train \(attributes.number, privacy: .public)")
        } catch {
            // Refused, or the ceiling is full. The local alert still stands, so the
            // journey is not left unannounced.
            Self.logger.error("Could not start a live journey: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Required by the scheduled-start API. It is what the system says when it brings
    /// the journey up on a device that was not looking.
    private static func alertConfiguration(for attributes: TrainActivityAttributes) -> AlertConfiguration {
        AlertConfiguration(
            title: "\(attributes.logo) \(attributes.number)",
            body: "Your train is coming up.",
            sound: .default
        )
    }

    // MARK: - Ending

    func end(tripID: UUID) async {
        guard let record = record(for: tripID) else { return }
        forget(tripID: tripID)

        guard let activity = Activity<TrainActivityAttributes>.activities.first(where: { $0.id == record.activityID }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// Takes down everything this app knows about, including anything left over from
    /// a previous install that the store no longer accounts for.
    func endAll() async {
        defaults.removeObject(forKey: Self.recordsKey)
        for activity in Activity<TrainActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Persistence

    private func records() -> [Record] {
        guard let data = defaults.data(forKey: Self.recordsKey),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return decoded
    }

    private func record(for tripID: UUID) -> Record? {
        records().first { $0.tripID == tripID }
    }

    private func store(_ record: Record) {
        var all = records().filter { $0.tripID != record.tripID }
        all.append(record)
        save(all)
    }

    private func forget(tripID: UUID) {
        save(records().filter { $0.tripID != tripID })
    }

    private func save(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey)
    }
}
