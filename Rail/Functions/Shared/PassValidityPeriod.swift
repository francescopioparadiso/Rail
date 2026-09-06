import Foundation

/// The stretch of time a pass covers, written the way a season ticket reads:
/// "September 2026" for a monthly one, "3-9 Mar 2026" for a weekly one.
///
/// Shared so a pass says the same thing in the mailbox it arrived in and in the
/// list it ends up in.
nonisolated enum PassValidityPeriod {

    // MARK: - Methods

    static func text(name: String, start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        return isWeekly(name: name, start: first, end: last)
            ? weekly(start: first, end: last)
            : monthly(first)
    }

    /// A fortnight or less reads as a week-long pass, and so does anything the
    /// operator actually called "Weekly".
    static func isWeekly(name: String, start: Date, end: Date) -> Bool {
        let days = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return days <= 14
            || name.caseInsensitiveCompare(String(localized: "Weekly")) == .orderedSame
    }

    // MARK: - Helpers

    private static func monthly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: date)
    }

    private static func weekly(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)

        let month = DateFormatter()
        month.locale = .current
        month.setLocalizedDateFormatFromTemplate("MMM")

        let year = DateFormatter()
        year.locale = .current
        year.setLocalizedDateFormatFromTemplate("yyyy")

        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)

        if sameMonth && sameYear {
            return "\(startDay)-\(endDay) \(month.string(from: start)) \(year.string(from: start))"
        }
        if sameYear {
            return "\(startDay) \(month.string(from: start))–\(endDay) \(month.string(from: end)) \(year.string(from: start))"
        }
        return "\(startDay) \(month.string(from: start)) \(year.string(from: start))–"
            + "\(endDay) \(month.string(from: end)) \(year.string(from: end))"
    }
}
