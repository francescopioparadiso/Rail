import Foundation

enum EmailProvider: String, Codable, CaseIterable, Sendable {
    case apple
    case google
    case microsoft
    case yahoo
    case aol
    case zoho
    case fastmail
    case gmx
    case libero
    case virgilio
    case tim
    case aruba
    case tiscali
    case other

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .microsoft: return "Microsoft"
        case .yahoo: return "Yahoo"
        case .aol: return "AOL"
        case .zoho: return "Zoho"
        case .fastmail: return "Fastmail"
        case .gmx: return "GMX"
        case .libero: return "Libero"
        case .virgilio: return "Virgilio"
        case .tim: return "TIM"
        case .aruba: return "Aruba"
        case .tiscali: return "Tiscali"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "icloud"
        default: return "envelope"
        }
    }

    var linkDestination: URL? {
        switch self {
        case .apple:
            return URL(string: "https://account.apple.com/account/manage/section/security")
        case .google:
            return URL(string: "https://myaccount.google.com/apppasswords")
        case .microsoft:
            return URL(string: "https://account.live.com/proofs/AppPassword")
        case .yahoo:
            return URL(string: "https://login.yahoo.com/account/security/app-passwords")
        case .aol:
            return URL(string: "https://login.aol.com/account/security/app-passwords")
        case .zoho:
            return URL(string: "https://accounts.zoho.com/home#security/security_pwd")
        case .fastmail:
            return URL(string: "https://www.fastmail.com/settings/security/apps/")
        case .gmx:
            return URL(string: "https://www.gmx.com/")
        case .libero:
            return URL(string: "https://login.libero.it/")
        case .virgilio:
            return URL(string: "https://login.virgilio.it/")
        case .tim:
            return URL(string: "https://www.tim.it/")
        case .aruba:
            return URL(string: "https://login.aruba.it/")
        case .tiscali:
            return URL(string: "https://mail.tiscali.it/")
        case .other:
            return nil
        }
    }

    nonisolated var server: String {
        switch self {
        case .apple: return "imap.mail.me.com"
        case .google: return "imap.gmail.com"
        case .microsoft: return "outlook.office365.com"
        case .yahoo: return "imap.mail.yahoo.com"
        case .aol: return "imap.aol.com"
        case .zoho: return "imap.zoho.com"
        case .fastmail: return "imap.fastmail.com"
        case .gmx: return "imap.gmx.com"
        case .libero: return "imapmail.libero.it"
        case .virgilio: return "in.virgilio.it"
        case .tim: return "in.alice.it"
        case .aruba: return "imaps.aruba.it"
        case .tiscali: return "imap.tiscali.it"
        case .other: return ""
        }
    }

    nonisolated var port: Int {
        993
    }

    /// Domains commonly associated with this provider.
    nonisolated var emailDomains: [String] {
        switch self {
        case .apple: return ["icloud.com", "me.com", "mac.com"]
        case .google: return ["gmail.com", "googlemail.com"]
        case .microsoft: return ["outlook.com", "hotmail.com", "live.com", "msn.com"]
        case .yahoo: return ["yahoo.com", "yahoo.it", "ymail.com", "rocketmail.com"]
        case .aol: return ["aol.com", "aim.com"]
        case .zoho: return ["zoho.com", "zohomail.com"]
        case .fastmail: return ["fastmail.com", "fastmail.fm"]
        case .gmx: return ["gmx.com", "gmx.net", "gmx.de", "gmx.it"]
        case .libero: return ["libero.it"]
        case .virgilio: return ["virgilio.it"]
        case .tim: return ["tim.it", "alice.it", "tin.it"]
        case .aruba: return ["aruba.it", "aruba.com"]
        case .tiscali: return ["tiscali.it"]
        case .other: return []
        }
    }

    /// Infers a provider from an email address domain. Unknown domains use `.other`.
    nonisolated static func inferred(from email: String) -> EmailProvider {
        let domain = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: "@")
            .last
            .map(String.init) ?? ""

        guard domain.contains(".") else { return .other }

        for provider in EmailProvider.allCases where provider != .other {
            if provider.emailDomains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) {
                return provider
            }
        }
        return .other
    }
}
