import Foundation

extension Pass {
    /// Names the PDF after the period it covers, so a folder of them sorts by date:
    /// a whole calendar month is `2026_07`, anything else `2026_07_01-2026_07_15`.
    var documentBaseName: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        let start = calendar.startOfDay(for: start_date)
        let end = calendar.startOfDay(for: expiry_date)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone

        if calendar.isDate(start, equalTo: end, toGranularity: .month),
           calendar.component(.day, from: start) == 1,
           let daysInMonth = calendar.range(of: .day, in: .month, for: start),
           calendar.component(.day, from: end) == daysInMonth.count {
            formatter.dateFormat = "yyyy_MM"
            return formatter.string(from: start)
        }

        formatter.dateFormat = "yyyy_MM_dd"
        let from = formatter.string(from: start)
        let to = formatter.string(from: end)
        return from == to ? from : "\(from)-\(to)"
    }

    var documentFilename: String { documentBaseName + ".pdf" }
}
