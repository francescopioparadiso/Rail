import Foundation

struct CalendarSettings: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var autoSyncToCalendar: Bool = true
    var calendarIdentifier: String = ""
    var titleFormat: String = "Train {number}"
    var travelTime: Double = 0

    init(
        id: UUID = UUID(),
        autoSyncToCalendar: Bool = true,
        calendarIdentifier: String = "",
        titleFormat: String = "Train {number}",
        travelTime: Double = 0
    ) {
        self.id = id
        self.autoSyncToCalendar = autoSyncToCalendar
        self.calendarIdentifier = calendarIdentifier
        self.titleFormat = titleFormat
        self.travelTime = travelTime
    }

    private enum CodingKeys: String, CodingKey {
        case id, autoSyncToCalendar, calendarIdentifier, titleFormat, travelTime
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        autoSyncToCalendar = try container.decodeIfPresent(Bool.self, forKey: .autoSyncToCalendar) ?? true
        calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier) ?? ""
        titleFormat = try container.decodeIfPresent(String.self, forKey: .titleFormat) ?? "Train {number}"
        travelTime = try container.decodeIfPresent(Double.self, forKey: .travelTime) ?? 0
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(autoSyncToCalendar, forKey: .autoSyncToCalendar)
        try container.encode(calendarIdentifier, forKey: .calendarIdentifier)
        try container.encode(titleFormat, forKey: .titleFormat)
        try container.encode(travelTime, forKey: .travelTime)
    }
}
