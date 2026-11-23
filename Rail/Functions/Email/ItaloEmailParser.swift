import Foundation
import PDFKit

/// Italo's "Conferma Acquisto" email. Unlike Trenitalia's, it holds the whole
/// ticket: the journey sits in its schema.org data, the seat beside it, and the
/// barcode and the PDF receipt travel as attachments. Nothing is looked up online.
/// A round trip is one email with two journeys (Andata, Ritorno), each with its own
/// train, seat and barcode image.
nonisolated enum ItaloEmailParser {
    struct Journey {
        /// The six-character ticket code, the same for both journeys of a round trip.
        let code: String
        /// 0 for the outbound (or only) journey, 1 for the return.
        let leg: Int
        let departureDate: Date
        let arrivalDate: Date?
        let trainNumber: String
        let departureStation: String
        let arrivalStation: String
        let passengerName: String
        let carriage: Int
        let seat: String
    }

    static func isItaloSender(_ address: String) -> Bool {
        address.lowercased().contains("italotreno")
    }

    /// A confirmation that did not come from Italo itself: a friend's forward or reply
    /// carries it as quoted text, with no schema.org data and often no attachments.
    static func looksLikeConfirmation(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("italotreno") && lower.contains("codice biglietto")
    }

    /// `html` is the message's HTML part; `emailDate` sets the year, which the
    /// email leaves out ("17/12"). One journey per leg, in order.
    nonisolated static func parseAll(html: String, emailDate: Date) -> [Journey] {
        let text = plainText(html)
        guard let code = capture(#""reservationNumber"\s*:\s*"([A-Z0-9]{5,8})""#, in: html)
                ?? capture(#""ticketNumber"\s*:\s*"([A-Z0-9]{5,8})""#, in: html)
                ?? capture(#"Codice biglietto\s+([A-Z0-9]{5,8})\b"#, in: text) else { return [] }

        let days = journeyDays(in: text, emailDate: emailDate)
        var legs = structuredLegs(in: html)
        // a forward drops the schema.org data and keeps only what the email shows
        if legs.isEmpty { legs = visibleLegs(in: text) }

        return legs.enumerated().compactMap { index, leg in
            guard index < days.count,
                  let departureDate = combine(day: days[index], clock: leg.departureClock) else { return nil }
            var arrivalDate = combine(day: days[index], clock: leg.arrivalClock)
            // an overnight run arrives the next day
            if let arrival = arrivalDate, arrival < departureDate {
                arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrival)
            }
            return Journey(
                code: code,
                leg: index,
                departureDate: departureDate,
                arrivalDate: arrivalDate,
                trainNumber: leg.trainNumber,
                departureStation: leg.departureStation,
                arrivalStation: leg.arrivalStation,
                passengerName: leg.passengerName,
                carriage: leg.carriage,
                seat: leg.seat
            )
        }
    }

    /// The total on the PDF receipt, "86.40 EUR", as the list prints prices.
    static func price(inPDF data: Data) -> String? {
        guard let document = PDFDocument(data: data), let text = document.string,
              let total = capture(#"TOTALE VIAGGIO\s+(\d+[.,]\d{2})"#, in: text),
              let value = Double(total.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return String(format: "%.2f €", value)
    }

    // MARK: - Helpers

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar
    }()

    private struct Leg {
        let trainNumber: String
        let departureStation: String
        let arrivalStation: String
        let departureClock: String
        let arrivalClock: String
        let passengerName: String
        let carriage: Int
        let seat: String
    }

    /// The journeys of the schema.org data: one `TrainReservation` each.
    nonisolated private static func structuredLegs(in html: String) -> [Leg] {
        let marked = html.replacingOccurrences(
            of: #""@type"\s*:\s*"TrainReservation""#, with: "\u{1}", options: .regularExpression
        )
        return marked.components(separatedBy: "\u{1}").dropFirst().compactMap { chunk in
            guard let trainNumber = capture(#""trainNumber"\s*:\s*"(\d+)""#, in: chunk),
                  let departureStation = capture(#""departureStation"\s*:\s*\{[^}]*?"name"\s*:\s*"([^"]+)""#, in: chunk),
                  let arrivalStation = capture(#""arrivalStation"\s*:\s*\{[^}]*?"name"\s*:\s*"([^"]+)""#, in: chunk),
                  let departureClock = capture(#""departureTime"\s*:\s*"(\d{1,2}:\d{2})""#, in: chunk),
                  let arrivalClock = capture(#""arrivalTime"\s*:\s*"(\d{1,2}:\d{2})""#, in: chunk) else { return nil }
            return Leg(
                trainNumber: trainNumber,
                departureStation: clean(departureStation),
                arrivalStation: clean(arrivalStation),
                departureClock: departureClock,
                arrivalClock: arrivalClock,
                passengerName: capture(#""underName"\s*:\s*"([^"]+)""#, in: chunk).map(clean) ?? "",
                carriage: capture(#""seatSection"\s*:\s*"\s*(\d+)\s*""#, in: chunk).flatMap { Int($0) } ?? 0,
                seat: capture(#""seatNumber"\s*:\s*"\s*([0-9A-Za-z]+)\s*""#, in: chunk) ?? ""
            )
        }
    }

    /// The journeys the email shows as text, "Itinerario A - B A B Orari N.Treno
    /// Ambiente 08:40 > 09:30 9923 Smart Carrozza Posto 9 33" under Andata and Ritorno.
    nonisolated private static func visibleLegs(in text: String) -> [Leg] {
        let pattern = #"Itinerario\s+(.+?)\s+Orari\s+N\.?\s*Treno\s+Ambiente\s+(\d{1,2}:\d{2})\s*>\s*(\d{1,2}:\d{2})\s+(\d{2,5})\s+.+?\s+Carrozza\s+Posto\s+(\d+)\s+([0-9A-Za-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let name = capture(#"Contatto (?:della )?prenotazione:\s*(.+?)\s+Codice biglietto"#, in: text).map { clean($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) } ?? ""

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            func group(_ number: Int) -> String? {
                Range(match.range(at: number), in: text).map { String(text[$0]) }
            }
            guard let itinerary = group(1), let departureClock = group(2), let arrivalClock = group(3),
                  let trainNumber = group(4), let carriage = group(5).flatMap({ Int($0) }), let seat = group(6) else { return nil }
            let stations = splitItinerary(itinerary)
            return Leg(
                trainNumber: trainNumber,
                departureStation: stations.departure,
                arrivalStation: stations.arrival,
                departureClock: departureClock,
                arrivalClock: arrivalClock,
                passengerName: name,
                carriage: carriage,
                seat: seat
            )
        }
    }

    /// "Torino P.S. - MI CENTRALE Torino P.S. MI CENTRALE": the route, then both names
    /// again, so the arrival is the repeated tail.
    nonisolated private static func splitItinerary(_ itinerary: String) -> (departure: String, arrival: String) {
        guard let dash = itinerary.range(of: " - ") else { return (clean(itinerary), "") }
        let departure = String(itinerary[..<dash.lowerBound])
        let rest = String(itinerary[dash.upperBound...])
        let length = (rest.count - departure.count - 2) / 2
        if length > 0 {
            let arrival = String(rest.prefix(length))
            if rest == arrival + " " + departure + " " + arrival { return (clean(departure), clean(arrival)) }
        }
        return (clean(departure), clean(rest))
    }

    /// The email's visible words: tags gone, entities decoded, spaces collapsed.
    nonisolated private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&gt;", ">"), ("&lt;", "<"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// The travel days from the "Data 17/12" boxes, one per journey. With no year in
    /// the email, each is the first such day not before the day the ticket was bought.
    nonisolated private static func journeyDays(in text: String, emailDate: Date) -> [Date] {
        guard let regex = try? NSRegularExpression(pattern: #"\bData\s+(\d{1,2})/(\d{1,2})\b"#) else { return [] }
        let bought = calendar.startOfDay(for: emailDate)
        let year = calendar.component(.year, from: bought)

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let dayRange = Range(match.range(at: 1), in: text),
                  let monthRange = Range(match.range(at: 2), in: text),
                  let day = Int(text[dayRange]), let month = Int(text[monthRange]) else { return nil }
            for candidate in [year, year + 1] {
                if let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
                   date >= bought { return date }
            }
            return nil
        }
    }

    nonisolated private static func combine(day: Date, clock: String) -> Date? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    nonisolated private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    nonisolated private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
