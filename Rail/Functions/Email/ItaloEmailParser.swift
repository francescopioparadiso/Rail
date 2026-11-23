import Foundation
import PDFKit

/// Italo's "Conferma Acquisto" email. Unlike Trenitalia's, it holds the whole
/// ticket: the journey sits in its schema.org data, the seat beside it, and the
/// barcode and the PDF receipt travel as attachments. Nothing is looked up online.
nonisolated enum ItaloEmailParser {
    struct Journey {
        /// The six-character ticket code.
        let code: String
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

    /// `html` is the message's HTML part; `emailDate` sets the year, which the
    /// email leaves out ("17/12").
    nonisolated static func parse(html: String, emailDate: Date) -> Journey? {
        guard let code = capture(#""reservationNumber"\s*:\s*"([A-Z0-9]{5,8})""#, in: html)
                ?? capture(#""ticketNumber"\s*:\s*"([A-Z0-9]{5,8})""#, in: html),
              let trainNumber = capture(#""trainNumber"\s*:\s*"(\d+)""#, in: html),
              let departureStation = capture(#""departureStation"\s*:\s*\{[^}]*?"name"\s*:\s*"([^"]+)""#, in: html),
              let arrivalStation = capture(#""arrivalStation"\s*:\s*\{[^}]*?"name"\s*:\s*"([^"]+)""#, in: html),
              let departureClock = capture(#""departureTime"\s*:\s*"(\d{1,2}:\d{2})""#, in: html),
              let arrivalClock = capture(#""arrivalTime"\s*:\s*"(\d{1,2}:\d{2})""#, in: html),
              let day = journeyDay(in: html, emailDate: emailDate),
              let departureDate = combine(day: day, clock: departureClock) else { return nil }

        var arrivalDate = combine(day: day, clock: arrivalClock)
        // an overnight run arrives the next day
        if let arrival = arrivalDate, arrival < departureDate {
            arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrival)
        }

        return Journey(
            code: code,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            trainNumber: trainNumber,
            departureStation: clean(departureStation),
            arrivalStation: clean(arrivalStation),
            passengerName: capture(#""underName"\s*:\s*"([^"]+)""#, in: html).map(clean) ?? "",
            carriage: capture(#""seatSection"\s*:\s*"\s*(\d+)\s*""#, in: html).flatMap { Int($0) } ?? 0,
            seat: capture(#""seatNumber"\s*:\s*"\s*([0-9A-Za-z]+)\s*""#, in: html) ?? ""
        )
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

    /// The travel day from the "Data 17/12" box. With no year in the email, it is
    /// the first such day not before the day the ticket was bought.
    nonisolated private static func journeyDay(in html: String, emailDate: Date) -> Date? {
        let text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let pattern = #"Data\s+(\d{1,2})/(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let day = Int(text[dayRange]), let month = Int(text[monthRange]) else { return nil }

        let bought = calendar.startOfDay(for: emailDate)
        let year = calendar.component(.year, from: bought)
        for candidate in [year, year + 1] {
            if let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
               date >= bought { return date }
        }
        return nil
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
