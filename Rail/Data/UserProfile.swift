import Foundation
import SwiftData

enum EmailProvider: String, Codable, CaseIterable {
    case apple
    case google

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "icloud"
        case .google: return "envelope"
        }
    }

    var linkDestination: URL {
        switch self {
        case .apple:
            return URL(string: "https://account.apple.com/account/manage/section/security")!
        case .google:
            return URL(string: "https://myaccount.google.com/apppasswords")!
        }
    }

    var linkTitle: String {
        switch self {
        case .apple: return "Generate App-Specific Password"
        case .google: return "Generate App Password"
        }
    }

    var linkDescription: String {
        switch self {
        case .apple:
            return "Enter your iCloud email and an App-Specific Password."
        case .google:
            return "Enter your Google email and an App Password. Note that 2-Step Verification must be enabled on your Google account."
        }
    }

    var server: String {
        switch self {
        case .apple: return "imap.mail.me.com"
        case .google: return "imap.gmail.com"
        }
    }

    var port: Int {
        switch self {
        case .apple: return 993
        case .google: return 993
        }
    }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var photo: Data?
    var calendarSettings: CalendarSettings = CalendarSettings()
    var emails: [Emails] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        photo: Data? = nil,
        calendarSettings: CalendarSettings = CalendarSettings(),
        emails: [Emails] = []
    ) {
        self.id = id
        self.name = name
        self.photo = photo
        self.calendarSettings = calendarSettings
        self.emails = emails
    }
}

struct CalendarSettings: Codable, Identifiable {
    var id: UUID = UUID()
    var autoSyncToCalendar: Bool = true
    var calendarIdentifier: String = ""
    var titleFormat: String = "Train {number}"
    var travelTime: Double = 0
}

struct Emails: Codable, Identifiable {
    var id: UUID = UUID()
    var provider: EmailProvider
    var email: String
    var appPassword: String
    var content: [EmailContent] = []
}

struct EmailContent: Codable, Identifiable {
    var id: UUID = UUID()
    var imapUID: String
    var date: Date
    var link: String
    var departureDate: Date?
    var trainNumber: String = ""
    var departureStation: String = ""
    var arrivalStation: String = ""
    var passengers: [EmailContentPassenger] = []

    var hasLoadedDetails: Bool {
        !passengers.isEmpty
    }

    // DEBUGGING: matches shouldFetchDetails cutoff in Emails.swift
    var isUpcoming: Bool {
        guard let departureDate else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
        return departureDate > cutoff
    }
}

enum CheckInLink {
    static let baseURL = "https://www.lefrecce.it/Channels.Website.WEB/#/self-check-in?id="

    static func url(for checkInID: String) -> String {
        baseURL + normalizeID(checkInID) + "&lang=it"
    }

    static func extractID(from url: String) -> String? {
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

    private static func normalizedID(from raw: String) -> String? {
        var id = raw.removingPercentEncoding ?? raw
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        id = id.trimmingCharacters(in: CharacterSet(charactersIn: ".,;\"'<>"))
        while id.hasSuffix("=") { id.removeLast() }
        guard id.count >= 20, id.allSatisfy({ $0.isLetter || $0.isNumber || "+/_-".contains($0) }) else { return nil }
        return id
    }
}

struct EmailContentPassenger: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var carriage: Int
    var seat: String
    var qrcode: Data
}