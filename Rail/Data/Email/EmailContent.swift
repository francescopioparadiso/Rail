import Foundation

struct EmailContent: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var imapUID: String
    var date: Date
    var link: String
    var departureDate: Date?
    var arrivalDate: Date?
    var trainNumber: String = ""
    var departureStation: String = ""
    var arrivalStation: String = ""
    var price: String = "Unknown"
    var passengers: [EmailContentPassenger] = []
    var detailsFetchedAt: Date?
    var detailsError: String?

    private enum CodingKeys: String, CodingKey {
        case id, imapUID, date, link, departureDate, arrivalDate
        case trainNumber, departureStation, arrivalStation, price
        case passengers, detailsFetchedAt, detailsError
    }

    nonisolated init(
        id: UUID = UUID(),
        imapUID: String,
        date: Date,
        link: String,
        departureDate: Date? = nil,
        arrivalDate: Date? = nil,
        trainNumber: String = "",
        departureStation: String = "",
        arrivalStation: String = "",
        price: String = "Unknown",
        passengers: [EmailContentPassenger] = [],
        detailsFetchedAt: Date? = nil,
        detailsError: String? = nil
    ) {
        self.id = id
        self.imapUID = imapUID
        self.date = date
        self.link = link
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.trainNumber = trainNumber
        self.departureStation = departureStation
        self.arrivalStation = arrivalStation
        self.price = price
        self.passengers = passengers
        self.detailsFetchedAt = detailsFetchedAt
        self.detailsError = detailsError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imapUID = try container.decode(String.self, forKey: .imapUID)
        date = try container.decode(Date.self, forKey: .date)
        link = try container.decode(String.self, forKey: .link)
        departureDate = try container.decodeIfPresent(Date.self, forKey: .departureDate)
        arrivalDate = try container.decodeIfPresent(Date.self, forKey: .arrivalDate)
        trainNumber = try container.decodeIfPresent(String.self, forKey: .trainNumber) ?? ""
        departureStation = try container.decodeIfPresent(String.self, forKey: .departureStation) ?? ""
        arrivalStation = try container.decodeIfPresent(String.self, forKey: .arrivalStation) ?? ""
        price = try container.decodeIfPresent(String.self, forKey: .price) ?? "Unknown"
        passengers = try container.decodeIfPresent([EmailContentPassenger].self, forKey: .passengers) ?? []
        detailsFetchedAt = try container.decodeIfPresent(Date.self, forKey: .detailsFetchedAt)
        detailsError = try container.decodeIfPresent(String.self, forKey: .detailsError)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(imapUID, forKey: .imapUID)
        try container.encode(date, forKey: .date)
        try container.encode(link, forKey: .link)
        try container.encodeIfPresent(departureDate, forKey: .departureDate)
        try container.encodeIfPresent(arrivalDate, forKey: .arrivalDate)
        try container.encode(trainNumber, forKey: .trainNumber)
        try container.encode(departureStation, forKey: .departureStation)
        try container.encode(arrivalStation, forKey: .arrivalStation)
        try container.encode(price, forKey: .price)
        try container.encode(passengers, forKey: .passengers)
        try container.encodeIfPresent(detailsFetchedAt, forKey: .detailsFetchedAt)
        try container.encodeIfPresent(detailsError, forKey: .detailsError)
    }

    var hasLoadedDetails: Bool {
        detailsFetchedAt != nil || !passengers.isEmpty
    }

    nonisolated var isImportEligible: Bool {
        guard let departureDate else { return false }
        return Self.isDepartureOnOrAfterToday(departureDate)
    }

    nonisolated var isPastDeparture: Bool {
        guard let departureDate else { return false }
        return departureDate < Date()
    }

    /// Check-in page details can enrich both upcoming and past email tickets.
    nonisolated var shouldFetchCheckInDetails: Bool {
        !isSampleTicket
            && detailsFetchedAt == nil
            && passengers.isEmpty
            && CheckInLink.extractID(from: link) != nil
    }

    nonisolated static func isUpcomingDeparture(_ departureDate: Date, now: Date = Date()) -> Bool {
        isDepartureOnOrAfterToday(departureDate, now: now)
    }

    nonisolated static func isDepartureOnOrAfterToday(_ departureDate: Date, now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar.startOfDay(for: departureDate) >= calendar.startOfDay(for: now)
    }

    /// Preview-only stubs that must never appear in a real mailbox sync.
    nonisolated var isSampleTicket: Bool {
        let sampleIDs = [
            "abc123def456ghi789jkl012",
            "mno345pqr678stu901vwx234",
            "yza567bcd890efg123hij456"
        ]
        if let id = CheckInLink.extractID(from: link), sampleIDs.contains(id) {
            return true
        }
        return ["1001", "1002", "1003"].contains(imapUID)
    }
}

enum CheckInLink {
    static let baseURL = "https://www.lefrecce.it/Channels.Website.WEB/#/self-check-in?id="

    static func url(for checkInID: String) -> String {
        baseURL + normalizeID(checkInID) + "&lang=it"
    }

    nonisolated static func extractID(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let idRange = trimmed.range(of: "id=") {
            let remainder = trimmed[idRange.upperBound...]
            let raw = remainder.split(separator: "&", maxSplits: 1).first.map(String.init) ?? ""
            return normalizedID(from: raw)
        }

        return normalizedID(from: trimmed)
    }

    static func normalizeID(_ raw: String) -> String {
        normalizedID(from: raw) ?? ""
    }

    nonisolated private static func normalizedID(from raw: String) -> String? {
        var id = raw.removingPercentEncoding ?? raw
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        id = id.trimmingCharacters(in: CharacterSet(charactersIn: ".,;\"'<>"))
        while id.hasSuffix("=") { id.removeLast() }
        guard id.count >= 16, id.allSatisfy({ $0.isLetter || $0.isNumber || "+/_-".contains($0) }) else { return nil }
        return id
    }
}

struct EmailContentPassenger: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var carriage: Int
    var seat: String
    var qrcode: Data
}
