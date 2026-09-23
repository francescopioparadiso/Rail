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
/// KNOWN LIMITATION — with the app closed, nothing recomputes which stop is next, but
/// the Lock Screen still moves on once. Every state carries the stop after its target,
/// and at the target's time the system flips the activity to stale and draws that stop
/// in the target's place (`ContentState.advanced(ifStale:)`), with no help from the app.
/// The stop after that one is not known until the app next runs, so a journey with
/// several stops between boarding and alighting stalls on the second. Carrying it
/// further needs background execution or a push from a server, and this app has neither
/// by design.
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
        /// What was last handed to it. An unchanged journey is left alone rather
        /// than pushed again: every update is a fresh render, and a re-render is
        /// exactly the moment the Lock Screen has nothing to draw.
        var contentHash: Int?

        func withContentHash(_ hash: Int) -> Record {
            var copy = self
            copy.contentHash = hash
            return copy
        }
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
            trains
                .compactMap { candidate(train: $0, stops: stopsByTrain[$0.id] ?? [], seats: seatsByTrain[$0.id] ?? [], now: now) }
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
                now: now
            )
        }
    }

    /// Starts or updates the one activity for a journey whose details the user has
    /// just opened.
    ///
    /// `sync` only ever reaches the two soonest departures, sorted across every
    /// train in the store; a journey opened directly from its details screen
    /// deserves its Live Activity whether or not it made that cut, so this is
    /// called from there instead of waiting on the next periodic sync.
    func startForOpenedDetails(train: Train, stops: [Stop], seats: [Seat], now: Date = Date()) async {
        guard areActivitiesEnabled,
              let candidate = candidate(train: train, stops: stops, seats: seats, now: now)
        else { return }

        await apply(state: candidate.state, train: candidate.train, stops: candidate.stops, now: now)
    }

    /// A journey worth a place on the Lock Screen, if there is one: not cancelled,
    /// resolvable into a state, and not already over.
    private func candidate(
        train: Train,
        stops: [Stop],
        seats: [Seat],
        now: Date
    ) -> (train: Train, state: TrainActivityAttributes.ContentState, stops: [Stop])? {
        guard !stops.isEmpty else { return nil }
        let journey = TrainJourney(train: train, stops: stops)
        guard !journey.isCancelled,
              var state = TrainActivityState.resolve(journey, now: now),
              !TrainActivitySchedule.isOver(journeyEnd: state.journeyEnd, now: now)
        else { return nil }
        state.ticket = .init(seats: seats)
        return (train, state, stops)
    }

    /// Starts, updates or replaces the one activity for a journey.
    private func apply(
        state: TrainActivityAttributes.ContentState,
        train: Train,
        stops: [Stop],
        now: Date
    ) async {
        let attributes = TrainActivityAttributes(train: train, stops: stops)
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

            // Nothing has moved, so there is nothing to say. Pushing identical
            // content would only cost another render.
            if record.contentHash == state.hashValue {
                return
            }

            switch await updateActivity(id: record.activityID, content: content, expectedStart: record.startDate, now: now) {
            case .updated:
                store(record.withContentHash(state.hashValue))
                return

            case .notYetStarted:
                // Scheduled but not running, so there is nothing to update and
                // certainly nothing to replace — tearing it down here would cancel
                // the very thing that is meant to appear an hour before boarding,
                // and do it again on every refresh.
                Self.logger.info("Live journey is still pending; leaving it be")
                return

            case .gone:
                Self.logger.info("Live journey has gone; asking for a new one")
                forget(tripID: train.id)
            }
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

    /// What came of trying to bring a live journey up to date.
    private enum UpdateOutcome {
        case updated
        /// Scheduled, but the system has not started it. Leave it alone.
        case notYetStarted
        /// Ended or dismissed; a new one is needed.
        case gone
    }

    // MARK: - ActivityKit

    /// How long a record is allowed to sit unfound past the moment it was meant to
    /// begin before it is given up on. A rebuild reinstalling the app, or the system
    /// simply forgetting, both leave a record pointing at an activity that will never
    /// come back; without a deadline that record blocks a fresh one forever.
    private static let notFoundGrace: TimeInterval = 120

    /// The one place that touches a stored activity id.
    ///
    /// Whether `Activity.activities` lists an activity the system has not started yet
    /// is not settled, so a miss is read as "not started" rather than "gone" — for a
    /// while. Getting that the wrong way round on the first ask is expensive: it would
    /// replace the activity on every single refresh, and each replacement is a fresh,
    /// blank render. But held past `expectedStart` by more than `notFoundGrace`, a
    /// miss can no longer be a scheduled activity patiently waiting its turn; it is
    /// one the system has lost track of, most often because the app was rebuilt out
    /// from under it, and holding out for it any longer would strand the journey with
    /// no Live Activity at all.
    private func updateActivity(
        id: String,
        content: ActivityContent<TrainActivityAttributes.ContentState>,
        expectedStart: Date,
        now: Date
    ) async -> UpdateOutcome {
        guard let activity = Activity<TrainActivityAttributes>.activities.first(where: { $0.id == id }) else {
            if now.timeIntervalSince(expectedStart) >= Self.notFoundGrace {
                return .gone
            }
            return .notYetStarted
        }

        switch activity.activityState {
        case .ended, .dismissed:
            return .gone
        case .pending:
            return .notYetStarted
        default:
            await activity.update(content)
            return .updated
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
                    journeyEnd: state.journeyEnd,
                    contentHash: state.hashValue
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
