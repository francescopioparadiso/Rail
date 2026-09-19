#if DEBUG
import ActivityKit
import Foundation
import os

/// A way to watch a scheduled Live Activity arrive without waiting an hour for a
/// real train.
///
/// The whole point of the scheduled start is that it happens with Rail closed, which
/// is the one thing a simulator and a debugger cannot show. So: tap the button, kill
/// the app, and put the phone down for a minute.
@MainActor
enum TrainActivityDebug {

    private static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "LiveActivity")

    /// Books a made-up journey to appear a minute from now.
    ///
    /// Boarding is set an hour and a minute out so the ordinary hour's lead lands
    /// where we want it, rather than by asking the scheduler for something special.
    static func scheduleTestActivity(in delay: TimeInterval = 60) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are switched off for Rail in Settings."
        }

        let now = Date()
        // A stop far enough out that the countdown has something to count.
        let boarding = now.addingTimeInterval(max(delay, 0) + TrainActivitySchedule.lead)

        let journey = TrainJourney(
            logo: "FR",
            number: "9612",
            isCancelled: false,
            calls: [
                call("Torino Porta Nuova", "3", boarding, delay: 0),
                call("Milano Centrale", "14", boarding.addingTimeInterval(55 * 60), delay: 4),
                call("Bologna Centrale", "17", boarding.addingTimeInterval(120 * 60), delay: 4),
                call("Roma Termini", "1", boarding.addingTimeInterval(190 * 60), delay: 4)
            ]
        )

        guard let state = TrainActivityState.resolve(journey, now: now) else {
            return "Could not build a state for the test journey."
        }

        let attributes = TrainActivityAttributes(
            logo: journey.logo,
            number: journey.number,
            departureName: "Torino Porta Nuova",
            arrivalName: "Roma Termini",
            seatLabel: "4 · 12A",
            trainID: testTrainID,
            seatID: testSeatID
        )

        let content = ActivityContent(state: state, staleDate: state.targetDate)

        do {
            let activity: Activity<TrainActivityAttributes>
            if delay > 0 {
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: AlertConfiguration(
                        title: "FR 9612",
                        body: "Your train is coming up.",
                        sound: .default
                    ),
                    start: now.addingTimeInterval(delay)
                )
            } else {
                // Straight onto the screen, for looking at rather than waiting for.
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard
                )
            }
            logger.info("Test live journey started, id \(activity.id, privacy: .public)")
            return delay > 0
                ? "Scheduled. Close Rail — it should appear in about \(Int(delay)) seconds."
                : "Started."
        } catch {
            return "Refused: \(error.localizedDescription)"
        }
    }

    /// Starts a test journey right now, with no waiting.
    ///
    /// Reachable from a launch argument so a simulator run can put a live journey on
    /// screen without anyone tapping anything — which is the only way to look at what
    /// the Lock Screen and the island actually draw.
    @discardableResult
    static func startTestActivityNow() async -> String {
        await scheduleTestActivity(in: 0)
    }

    /// Set by `-rail-preview-activity`: draws the Lock Screen view inside the app,
    /// where a mistake is visible rather than being a blank rectangle.
    static var isPreviewRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-rail-preview-activity")
    }

    /// Set by `-rail-test-activity` on the command line. Debug builds only.
    static var isLaunchTestRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-rail-test-activity")
    }

    /// Takes down everything, test journeys included.
    static func endAll() async {
        await TrainActivityManager.shared.endAll()
    }

    // MARK: - Helpers

    /// Ids that match nothing in the store, so tapping the test activity exercises
    /// the deep link's fallback to the main screen.
    private static let testTrainID = UUID(uuidString: "DEADBEEF-0000-0000-0000-00000000FEED")!
    private static let testSeatID = UUID(uuidString: "DEADBEEF-0000-0000-0000-00000000BEEF")!

    private static func call(_ name: String, _ platform: String, _ at: Date, delay: Int) -> TrainJourney.Call {
        let effective = at.addingTimeInterval(TimeInterval(delay * 60))
        return TrainJourney.Call(
            name: name,
            platform: platform,
            isSelected: true,
            isCancelled: false,
            isCompleted: false,
            refTime: at,
            departureScheduled: at,
            departureEffective: effective,
            arrivalScheduled: at,
            arrivalEffective: effective,
            departureDelay: delay,
            arrivalDelay: delay
        )
    }
}
#endif
