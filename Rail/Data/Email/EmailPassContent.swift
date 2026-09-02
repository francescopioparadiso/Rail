import Foundation

struct EmailPassContent: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var imapUID: String
    var date: Date
    var name: String
    var startDate: Date
    var endDate: Date
    var price: String = ""
    var qrcode: Data
    /// Staged source PDF, resolved through `PassPDFStore` at import time.
    var pdfFilename: String?
    var parseError: String?

    nonisolated var isImportEligible: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar.startOfDay(for: endDate) >= calendar.startOfDay(for: Date())
    }

    nonisolated var fingerprint: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(name.lowercased())|\(formatter.string(from: startDate))|\(formatter.string(from: endDate))"
    }
}
