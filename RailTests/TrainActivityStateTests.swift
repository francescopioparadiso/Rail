import Foundation
import Testing

@testable import Rail

/// The rules that decide what a live journey shows.
///
/// Every case is built as a whole run and put through `resolve`, so these test the
/// rules rather than the shape of the struct.
@MainActor
struct TrainActivityStateTests {

    private typealias Leg = TrainActivitySample.Leg
    private let now = TrainActivitySample.reference

    // MARK: - Rows and target

    @Test("Before the train has left its origin there are two rows, aimed at boarding")
    func notDeparted() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.notDeparted, now: now))

        #expect(state.hasDeparted == false)
        #expect(state.departure.name == "Torino Porta Nuova")
        #expect(state.arrival.name == "Roma Termini")
        #expect(state.targetRole == .departure)
        #expect(state.targetName == "Torino Porta Nuova")
    }

    @Test("A running train counts down to the stop between the two ends, naming it")
    func departedWithIntermediate() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.enRoute, now: now))

        #expect(state.hasDeparted)
        #expect(state.targetRole == .intermediate)
        // Only the two ends get rows, so this stop is named by the countdown alone.
        #expect(state.targetName == "Bologna Centrale")
        #expect(state.departure.name != state.targetName)
        #expect(state.arrival.name != state.targetName)
    }

    @Test("A boarding station the train has not reached wins over any later stop")
    func targetIsBoardingEvenWhenRunning() throws {
        // The train has left its origin but has not called at the boarding station,
        // which is further down the line.
        let journey = TrainActivitySample.journey([
            Leg(name: "Napoli Centrale", platform: "20", minutes: -40, isSelected: false, isCompleted: true),
            Leg(name: "Roma Termini", platform: "1", minutes: 30),
            Leg(name: "Firenze S.M.N.", platform: "9", minutes: 120),
            Leg(name: "Milano Centrale", platform: "14", minutes: 220)
        ])
        let state = try #require(TrainActivityState.resolve(journey, now: now))

        #expect(state.hasDeparted)
        #expect(state.targetRole == .departure)
        #expect(state.targetName == "Roma Termini")
        // Aimed at the boarding station itself, which is a drawn row.
        #expect(state.departure.name == state.targetName)
    }

    @Test("Once the last intermediate stop is behind it, the target is the end of the journey")
    func nextIsArrival() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.nextIsArrival, now: now))

        #expect(state.targetRole == .arrival)
        #expect(state.targetName == "Roma Termini")
        #expect(state.arrival.name == state.targetName)
    }

    @Test("A target already behind us leaves the activity stale, which is what reads Now")
    func arrivingNow() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.arrivingNow, now: now))

        #expect(state.targetRole == .arrival)
        // The stale date is the target, so the system flips the view to "Now" with
        // no app code running.
        #expect(state.targetDate <= now)
    }

    @Test("A leg inside a longer service uses the chosen stops, not the train's own ends")
    func midRouteLeg() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.midRoute, now: now))

        #expect(state.departure.name == "Milano Centrale")
        #expect(state.arrival.name == "Firenze S.M.N.")
        #expect(state.targetName == "Bologna Centrale")
        // Roma Termini is on the run but past where we get off, so it is never shown.
        #expect(state.targetName != "Roma Termini")
    }

    @Test("The platform shown is the target's, and follows the target as it moves")
    func platformFollowsTarget() throws {
        let beforeBoarding = try #require(TrainActivityState.resolve(TrainActivitySample.notDeparted, now: now))
        #expect(beforeBoarding.platform == "3")

        let enRoute = try #require(TrainActivityState.resolve(TrainActivitySample.enRoute, now: now))
        #expect(enRoute.platform == "17")
    }

    @Test("A delay moves every time without touching the timetable's")
    func delayed() throws {
        let state = try #require(TrainActivityState.resolve(TrainActivitySample.delayed, now: now))

        #expect(state.arrival.delay == 12)
        #expect(state.arrival.effective == state.arrival.scheduled.addingTimeInterval(12 * 60))
        // The countdown is aimed at the delay-adjusted time, never the booked one.
        #expect(state.targetRole == .intermediate)
        #expect(state.targetDate > now)
    }

    @Test("A stop struck from the run is never the target")
    func cancelledStopSkipped() throws {
        let journey = TrainActivitySample.journey([
            Leg(name: "Torino Porta Nuova", platform: "3", minutes: -60, isCompleted: true),
            Leg(name: "Vercelli", platform: "2", minutes: 20, isCancelled: true),
            Leg(name: "Milano Centrale", platform: "14", minutes: 70),
            Leg(name: "Roma Termini", platform: "1", minutes: 200)
        ])
        let state = try #require(TrainActivityState.resolve(journey, now: now))

        #expect(state.targetName == "Milano Centrale")
        #expect(state.targetRole == .intermediate)
    }

    @Test("A journey with nothing chosen has nothing to show")
    func noChosenStops() {
        let journey = TrainActivitySample.journey([
            Leg(name: "Torino Porta Nuova", platform: "3", minutes: 10, isSelected: false),
            Leg(name: "Milano Centrale", platform: "14", minutes: 80, isSelected: false)
        ])
        #expect(TrainActivityState.resolve(journey, now: now) == nil)
    }

    // MARK: - Scheduling

    @Test("A journey goes live an hour before boarding")
    func startsAnHourBefore() throws {
        let boarding = now.addingTimeInterval(3 * 3600)
        let end = boarding.addingTimeInterval(2 * 3600)

        let start = try #require(TrainActivitySchedule.start(boarding: boarding, journeyEnd: end, now: now))
        #expect(start == boarding.addingTimeInterval(-3600))
        #expect(TrainActivitySchedule.shouldStartImmediately(boarding: boarding, now: now) == false)
    }

    @Test("Boarding inside the hour is started now rather than scheduled")
    func startsImmediatelyInsideTheHour() {
        let boarding = now.addingTimeInterval(20 * 60)
        #expect(TrainActivitySchedule.shouldStartImmediately(boarding: boarding, now: now))
    }

    @Test("A long run starts later so it is still alive on arrival")
    func clampsForTheEightHourWall() throws {
        // Boarding in two hours, arriving eleven hours from now. Starting an hour
        // before boarding would spend the whole allowance long before the end.
        let boarding = now.addingTimeInterval(2 * 3600)
        let end = now.addingTimeInterval(11 * 3600)

        let start = try #require(TrainActivitySchedule.start(boarding: boarding, journeyEnd: end, now: now))
        #expect(start == end.addingTimeInterval(-TrainActivitySchedule.safeSpan))
        // Still alive when we get off, with an hour of the cap to spare.
        #expect(end.timeIntervalSince(start) <= TrainActivitySchedule.systemCap)
        #expect(start > boarding.addingTimeInterval(-3600))
    }

    @Test("A start is never asked for in the past")
    func neverSchedulesInThePast() throws {
        let boarding = now.addingTimeInterval(10 * 60)
        let end = boarding.addingTimeInterval(3600)

        let start = try #require(TrainActivitySchedule.start(boarding: boarding, journeyEnd: end, now: now))
        #expect(start >= now)
    }

    @Test("Boarding already past leaves nothing to schedule")
    func noStartOnceBoardingHasPassed() {
        let boarding = now.addingTimeInterval(-5 * 60)
        #expect(TrainActivitySchedule.start(boarding: boarding, journeyEnd: now.addingTimeInterval(3600), now: now) == nil)
    }

    // MARK: - Restarting

    @Test("An activity near the wall with journey left is replaced")
    func restartsAfterSevenHours() {
        let started = now.addingTimeInterval(-7 * 3600 - 60)
        let end = now.addingTimeInterval(2 * 3600)
        #expect(TrainActivitySchedule.shouldRestart(startedAt: started, journeyEnd: end, now: now))
    }

    @Test("A younger activity is left alone")
    func doesNotRestartEarly() {
        let started = now.addingTimeInterval(-3 * 3600)
        let end = now.addingTimeInterval(2 * 3600)
        #expect(TrainActivitySchedule.shouldRestart(startedAt: started, journeyEnd: end, now: now) == false)
    }

    @Test("An old activity for a journey that is over is not put back on screen")
    func doesNotRestartAFinishedJourney() {
        let started = now.addingTimeInterval(-8 * 3600)
        let end = now.addingTimeInterval(-10 * 60)
        #expect(TrainActivitySchedule.shouldRestart(startedAt: started, journeyEnd: end, now: now) == false)
        #expect(TrainActivitySchedule.isOver(journeyEnd: end, now: now))
    }
}
