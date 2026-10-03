import Foundation
import Testing

@testable import Rail

/// Which runs the operators' feeds may still be asked about.
@MainActor
struct TrainProgressFetchTests {

    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!

    private func stops(from start: Date, to end: Date) -> [Stop] {
        [(start, start), (end, end)].map { arrival, departure in
            Stop(
                id: UUID(), name: "S", platform: "", weather: "", is_selected: true, status: 0,
                is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0,
                dep_time_id: departure, arr_time_id: arrival,
                dep_time_eff: departure, arr_time_eff: arrival, ref_time: arrival
            )
        }
    }

    @Test("A run departing today is fetched")
    func today() {
        let run = stops(from: now.addingTimeInterval(3600), to: now.addingTimeInterval(7200))
        #expect(TrainProgress.canFetch(stops: run, now: now))
    }

    @Test("A night train that left yesterday and is still running is fetched")
    func overnight() {
        let run = stops(from: now.addingTimeInterval(-12 * 3600), to: now.addingTimeInterval(3600))
        #expect(TrainProgress.canFetch(stops: run, now: now))
    }

    @Test("Yesterday's finished run is not, so today's train cannot overwrite it")
    func yesterday() {
        let run = stops(from: now.addingTimeInterval(-30 * 3600), to: now.addingTimeInterval(-27 * 3600))
        #expect(!TrainProgress.canFetch(stops: run, now: now))
    }

    @Test("A run that ended today but long ago is not")
    func endedHoursAgo() {
        let run = stops(from: now.addingTimeInterval(-8 * 3600), to: now.addingTimeInterval(-5 * 3600))
        #expect(!TrainProgress.canFetch(stops: run, now: now))
    }
}
