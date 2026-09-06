import Foundation

struct NotificationSettings: Codable, Identifiable, Sendable, Equatable {
    // MARK: - Properties

    var id: UUID = UUID()
    var isEnabled: Bool = false
    var departureLead: Double = 1800
    var arrivalLead: Double = 1200

    /// How far ahead of a pass running out to say so, counted in `passLeadUnit`.
    var passLeadValue: Int = 3
    var passLeadUnit: PassLeadUnit = .days

    // MARK: - Types

    enum PassLeadUnit: Int, Codable, Sendable, CaseIterable {
        case days = 0
        case weeks = 1
    }

    // MARK: - Computed

    var hasAnyLead: Bool { departureLead > 0 || arrivalLead > 0 || passLeadDays > 0 }

    /// The pass warning in plain days, whichever unit it was written in.
    var passLeadDays: Int {
        let value = max(0, passLeadValue)
        return passLeadUnit == .weeks ? value * 7 : value
    }

    // MARK: - Lifecycle

    init(
        id: UUID = UUID(),
        isEnabled: Bool = false,
        departureLead: Double = 1800,
        arrivalLead: Double = 1200,
        passLeadValue: Int = 3,
        passLeadUnit: PassLeadUnit = .days
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.departureLead = departureLead
        self.arrivalLead = arrivalLead
        self.passLeadValue = passLeadValue
        self.passLeadUnit = passLeadUnit
    }

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, departureLead, arrivalLead, passLeadValue, passLeadUnit
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        departureLead = try container.decodeIfPresent(Double.self, forKey: .departureLead) ?? 1800
        arrivalLead = try container.decodeIfPresent(Double.self, forKey: .arrivalLead) ?? 1200
        passLeadValue = try container.decodeIfPresent(Int.self, forKey: .passLeadValue) ?? 3
        passLeadUnit = try container.decodeIfPresent(PassLeadUnit.self, forKey: .passLeadUnit) ?? .days
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(departureLead, forKey: .departureLead)
        try container.encode(arrivalLead, forKey: .arrivalLead)
        try container.encode(passLeadValue, forKey: .passLeadValue)
        try container.encode(passLeadUnit, forKey: .passLeadUnit)
    }

    // MARK: - Methods

    /// Spells out a lead the way the system spells durations, so the alert copy
    /// reads in the reader's language without a string table entry per option.
    static func leadDescription(_ seconds: Double) -> String {
        leadFormatter.string(from: seconds) ?? ""
    }

    private static let leadFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()
}
