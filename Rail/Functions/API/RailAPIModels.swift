import Foundation

// a station name paired with its lefrecce location id (e.g. "830001700"),
// used as departureLocationId / arrivalLocationId when fetching solutions.
struct StationSuggestion: Hashable {
    let name: String
    let code: String
}

// one leg of a journey solution (a train or a replacement bus).
struct SolutionSegment: Hashable {
    let origin: String
    let destination: String
    let departureTime: Date
    let arrivalTime: Date
    let logo: String        // train type acronym, e.g. "FR", "REG"
    let number: String      // train/bus number, e.g. "9512", "FI451"; empty when untracked
    let stationCode: String // bdoOrigin, e.g. "S08409", used to resolve the identifier
    let isBus: Bool         // true for bus-substitution legs (acronym "BU" / "Autobus")
    /// Legs lefrecce reports without a train number — urban transfers between
    /// stations in the same city. They're part of the journey and its timings,
    /// but there's no service to look up or follow, so they're never saved.
    let isUntracked: Bool

    init(
        origin: String,
        destination: String,
        departureTime: Date,
        arrivalTime: Date,
        logo: String,
        number: String,
        stationCode: String,
        isBus: Bool,
        isUntracked: Bool = false
    ) {
        self.origin = origin
        self.destination = destination
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.logo = logo
        self.number = number
        self.stationCode = stationCode
        self.isBus = isBus
        self.isUntracked = isUntracked
    }
}

// a full journey from departure to arrival; more than one segment means a connection.
struct Solution: Hashable, Identifiable {
    // MARK: - Properties

    let id = UUID()
    let segments: [SolutionSegment]
    /// nil when the fare is unavailable or the API asks us to hide it.
    let price: Double?
    let currency: String

    init(segments: [SolutionSegment], price: Double? = nil, currency: String = "\u{20AC}") {
        self.segments = segments
        self.price = price
        self.currency = currency
    }

    // MARK: - Computed

    var departureTime: Date { segments.first?.departureTime ?? .distantPast }
    var arrivalTime: Date { segments.last?.arrivalTime ?? .distantPast }
    var changeCount: Int { max(0, segments.count - 1) }
    var trackableSegments: [SolutionSegment] { segments.filter { !$0.isUntracked } }
    var durationMinutes: Int { max(0, Int(arrivalTime.timeIntervalSince(departureTime)) / 60) }
}

/// "1h 9m" / "2h" / "45m"
func journeyDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder)m" }
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
}
