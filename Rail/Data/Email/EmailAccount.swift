import Foundation

struct Emails: Codable, Identifiable, Sendable {
    /// Bump when ticket email parsing changes to force one full mailbox rescan.
    static let currentSyncGenerator = 9
    /// Bump when pass email parsing changes to force one full mailbox rescan.
    static let currentPassSyncGenerator = 4

    var id: UUID = UUID()
    var provider: EmailProvider
    var email: String
    var appPassword: String
    /// Used when `provider == .other`.
    var customIMAPServer: String?
    /// Used when `provider == .other`. Defaults to 993 if unset.
    var customIMAPPort: Int?
    var content: [EmailContent] = []
    var passes: [EmailPassContent] = []
    var lastSyncedUID: UInt64?
    var lastSyncedPassUID: UInt64?
    var imapUIDValidity: UInt64?
    /// UIDVALIDITY for the pass mailbox (Gmail All Mail), separate from ticket INBOX.
    var passImapUIDValidity: UInt64?
    var pendingFailedUIDs: [UInt64]?
    var pendingFailedPassUIDs: [UInt64]?
    var syncGenerator: Int?
    var passSyncGenerator: Int?

    var needsFullMailboxScan: Bool {
        lastSyncedUID == nil || (syncGenerator ?? 0) < Self.currentSyncGenerator
    }

    var needsFullPassMailboxScan: Bool {
        lastSyncedPassUID == nil || (passSyncGenerator ?? 0) < Self.currentPassSyncGenerator
    }

    nonisolated var imapServer: String {
        if provider == .other {
            return customIMAPServer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return provider.server
    }

    nonisolated var imapPort: Int {
        if provider == .other {
            return customIMAPPort ?? provider.port
        }
        return provider.port
    }

    /// Enough fields filled to attempt an IMAP login.
    nonisolated var hasConfiguredCredentials: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty, trimmedEmail.contains("@") else {
            return false
        }
        if provider == .other {
            return !imapServer.isEmpty
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, email, appPassword
        case customIMAPServer, customIMAPPort
        case content, passes
        case lastSyncedUID, lastSyncedPassUID, imapUIDValidity, passImapUIDValidity
        case pendingFailedUIDs, pendingFailedPassUIDs
        case syncGenerator, passSyncGenerator
    }

    nonisolated init(
        id: UUID = UUID(),
        provider: EmailProvider,
        email: String,
        appPassword: String,
        customIMAPServer: String? = nil,
        customIMAPPort: Int? = nil,
        content: [EmailContent] = [],
        passes: [EmailPassContent] = [],
        lastSyncedUID: UInt64? = nil,
        lastSyncedPassUID: UInt64? = nil,
        imapUIDValidity: UInt64? = nil,
        passImapUIDValidity: UInt64? = nil,
        pendingFailedUIDs: [UInt64]? = nil,
        pendingFailedPassUIDs: [UInt64]? = nil,
        syncGenerator: Int? = nil,
        passSyncGenerator: Int? = nil
    ) {
        self.id = id
        self.provider = provider
        self.email = email
        self.appPassword = appPassword
        self.customIMAPServer = customIMAPServer
        self.customIMAPPort = customIMAPPort
        self.content = content
        self.passes = passes
        self.lastSyncedUID = lastSyncedUID
        self.lastSyncedPassUID = lastSyncedPassUID
        self.imapUIDValidity = imapUIDValidity
        self.passImapUIDValidity = passImapUIDValidity
        self.pendingFailedUIDs = pendingFailedUIDs
        self.pendingFailedPassUIDs = pendingFailedPassUIDs
        self.syncGenerator = syncGenerator
        self.passSyncGenerator = passSyncGenerator
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try container.decodeIfPresent(EmailProvider.self, forKey: .provider) ?? .apple
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        appPassword = try container.decodeIfPresent(String.self, forKey: .appPassword) ?? ""
        customIMAPServer = try container.decodeIfPresent(String.self, forKey: .customIMAPServer)
        customIMAPPort = try container.decodeIfPresent(Int.self, forKey: .customIMAPPort)
        content = try container.decodeIfPresent([EmailContent].self, forKey: .content) ?? []
        passes = try container.decodeIfPresent([EmailPassContent].self, forKey: .passes) ?? []
        lastSyncedUID = try container.decodeIfPresent(UInt64.self, forKey: .lastSyncedUID)
        lastSyncedPassUID = try container.decodeIfPresent(UInt64.self, forKey: .lastSyncedPassUID)
        imapUIDValidity = try container.decodeIfPresent(UInt64.self, forKey: .imapUIDValidity)
        passImapUIDValidity = try container.decodeIfPresent(UInt64.self, forKey: .passImapUIDValidity)
        pendingFailedUIDs = try container.decodeIfPresent([UInt64].self, forKey: .pendingFailedUIDs)
        pendingFailedPassUIDs = try container.decodeIfPresent([UInt64].self, forKey: .pendingFailedPassUIDs)
        syncGenerator = try container.decodeIfPresent(Int.self, forKey: .syncGenerator)
        passSyncGenerator = try container.decodeIfPresent(Int.self, forKey: .passSyncGenerator)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(email, forKey: .email)
        try container.encode(appPassword, forKey: .appPassword)
        try container.encodeIfPresent(customIMAPServer, forKey: .customIMAPServer)
        try container.encodeIfPresent(customIMAPPort, forKey: .customIMAPPort)
        try container.encode(content, forKey: .content)
        try container.encode(passes, forKey: .passes)
        try container.encodeIfPresent(lastSyncedUID, forKey: .lastSyncedUID)
        try container.encodeIfPresent(lastSyncedPassUID, forKey: .lastSyncedPassUID)
        try container.encodeIfPresent(imapUIDValidity, forKey: .imapUIDValidity)
        try container.encodeIfPresent(passImapUIDValidity, forKey: .passImapUIDValidity)
        try container.encodeIfPresent(pendingFailedUIDs, forKey: .pendingFailedUIDs)
        try container.encodeIfPresent(pendingFailedPassUIDs, forKey: .pendingFailedPassUIDs)
        try container.encodeIfPresent(syncGenerator, forKey: .syncGenerator)
        try container.encodeIfPresent(passSyncGenerator, forKey: .passSyncGenerator)
    }
}
