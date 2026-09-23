import Foundation
import Testing

@testable import Rail

/// Which passenger the Lock Screen shows, and whether it shows one at all.
@MainActor
struct TrainActivityTicketTests {

    private func seat(_ carriage: String, _ number: String, qr: Data? = nil) -> Seat {
        Seat(id: UUID(), trainID: UUID(), name: "Passenger", carriage: carriage, number: number, image: qr)
    }

    @Test("A passenger with a coach and a seat is shown as both")
    func coachAndSeat() throws {
        let first = seat("4", "12A")
        let ticket = try #require(TrainActivityAttributes.ContentState.Ticket(seats: [first]))

        #expect(ticket.label == "4 – 12A")
        #expect(ticket.seatID == first.id)
    }

    @Test("The QR code is not needed for the seat to appear")
    func noQRCode() {
        #expect(TrainActivityAttributes.ContentState.Ticket(seats: [seat("4", "12A", qr: nil)]) != nil)
    }

    @Test("Either half alone is enough, and stands without a dot")
    func oneHalf() throws {
        #expect(try #require(TrainActivityAttributes.ContentState.Ticket(seats: [seat("4", "")])).label == "4")
        #expect(try #require(TrainActivityAttributes.ContentState.Ticket(seats: [seat("", "12A")])).label == "12A")
    }

    @Test("Nobody with a seat means no ticket, however many passengers there are")
    func nobodyHasASeat() {
        #expect(TrainActivityAttributes.ContentState.Ticket(seats: []) == nil)
        #expect(TrainActivityAttributes.ContentState.Ticket(seats: [seat("", ""), seat("  ", " ")]) == nil)
    }

    @Test("The first passenger who has a seat is the one shown")
    func firstWithASeat() throws {
        let second = seat("7", "3C")
        let ticket = try #require(TrainActivityAttributes.ContentState.Ticket(seats: [seat("", ""), second, seat("1", "1A")]))

        #expect(ticket.seatID == second.id)
    }

    @Test("A seat added later changes the state, so the running activity is updated")
    func addedSeatChangesState() throws {
        var before = TrainActivitySample.state(TrainActivitySample.enRoute)
        var after = before
        after.ticket = TrainActivityAttributes.ContentState.Ticket(seats: [seat("4", "12A")])

        #expect(before.ticket == nil)
        #expect(after.ticket != nil)
        #expect(before != after)

        before.ticket = after.ticket
        #expect(before == after)
    }
}
