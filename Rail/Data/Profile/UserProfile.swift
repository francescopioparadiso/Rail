import Foundation
import SwiftData
import CoreData

@Model
final class UserProfile {
    // MARK: - Properties

    var id: UUID = UUID()
    var name: String = ""
    @Attribute(.externalStorage) var photo: Data?
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

    // MARK: - Methods

    /// Prefers the richest profile so a blank local stub never hides CloudKit data.
    static func primary(from profiles: [UserProfile]) -> UserProfile? {
        profiles.max(by: { completenessScore(of: $0) < completenessScore(of: $1) })
    }

    /// Waits briefly for CloudKit import, merges duplicate profiles, then creates one only if still missing.
    @MainActor
    static func maintainSyncedProfile(in context: ModelContext) async {
        reconcile(in: context, createIfNeeded: false)

        let existing = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if existing.contains(where: { completenessScore(of: $0) > 0 }) {
            return
        }

        let remoteChanges = NotificationCenter.default.notifications(
            named: .NSPersistentStoreRemoteChange
        )
        let importWait = Task {
            try await Task.sleep(for: .seconds(4))
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = await importWait.result
            }
            group.addTask { @MainActor in
                for await _ in remoteChanges {
                    reconcile(in: context, createIfNeeded: false)
                    let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
                    if profiles.contains(where: { completenessScore(of: $0) > 0 }) {
                        importWait.cancel()
                        break
                    }
                }
            }
            await group.next()
            group.cancelAll()
        }

        reconcile(in: context, createIfNeeded: true)
    }

    @MainActor
    @discardableResult
    static func reconcile(in context: ModelContext, createIfNeeded: Bool) -> UserProfile? {
        let profiles: [UserProfile]
        do {
            profiles = try context.fetch(FetchDescriptor<UserProfile>())
        } catch {
            return nil
        }

        if profiles.isEmpty {
            guard createIfNeeded else { return nil }
            let profile = UserProfile()
            context.insert(profile)
            try? context.save()
            return profile
        }

        guard let winner = primary(from: profiles) else { return nil }
        let losers = profiles.filter { $0.persistentModelID != winner.persistentModelID }
        guard !losers.isEmpty else { return winner }

        for loser in losers {
            merge(loser, into: winner)
            context.delete(loser)
        }
        try? context.save()
        return winner
    }

    private static func completenessScore(of profile: UserProfile) -> Int {
        var score = 0
        if !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 10 }
        if let photo = profile.photo, !photo.isEmpty { score += 5 }
        score += calendarScore(profile.calendarSettings)
        for account in profile.emails {
            score += 20
            if !account.appPassword.isEmpty { score += 10 }
            score += min(account.content.count, 50)
        }
        return score
    }

    private static func calendarScore(_ settings: CalendarSettings) -> Int {
        var score = 0
        if !settings.calendarIdentifier.isEmpty { score += 3 }
        if settings.titleFormat != "Train {number}" { score += 2 }
        if settings.travelTime != 0 { score += 2 }
        if !settings.autoSyncToCalendar { score += 1 }
        return score
    }

    private static func merge(_ source: UserProfile, into target: UserProfile) {
        let targetName = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetName.isEmpty, !sourceName.isEmpty {
            target.name = source.name
        }

        switch (target.photo, source.photo) {
        case (nil, let sourcePhoto?):
            target.photo = sourcePhoto
        case (let targetPhoto?, let sourcePhoto?) where sourcePhoto.count > targetPhoto.count:
            target.photo = sourcePhoto
        default:
            break
        }

        if calendarScore(source.calendarSettings) > calendarScore(target.calendarSettings) {
            target.calendarSettings = source.calendarSettings
        }

        var emails = target.emails
        for sourceEmail in source.emails {
            if let index = emails.firstIndex(where: {
                $0.email.compare(sourceEmail.email, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                emails[index] = mergedEmail(emails[index], sourceEmail)
            } else {
                emails.append(sourceEmail)
            }
        }
        target.emails = emails
    }

    private static func mergedEmail(_ existing: Emails, _ incoming: Emails) -> Emails {
        var result = existing
        if result.appPassword.isEmpty, !incoming.appPassword.isEmpty {
            result.appPassword = incoming.appPassword
        }
        if result.provider != incoming.provider, !incoming.appPassword.isEmpty {
            result.provider = incoming.provider
        }

        var content = existing.content
        for ticket in incoming.content {
            if let index = content.firstIndex(where: { $0.id == ticket.id || $0.imapUID == ticket.imapUID }) {
                if !ticket.passengers.isEmpty, content[index].passengers.isEmpty {
                    content[index] = ticket
                }
            } else {
                content.append(ticket)
            }
        }
        result.content = content

        var passes = existing.passes
        for pass in incoming.passes {
            if let index = passes.firstIndex(where: {
                $0.id == pass.id || $0.imapUID == pass.imapUID || $0.fingerprint == pass.fingerprint
            }) {
                if passes[index].qrcode.isEmpty, !pass.qrcode.isEmpty {
                    passes[index] = pass
                }
            } else {
                passes.append(pass)
            }
        }
        result.passes = passes

        if let incomingUID = incoming.lastSyncedUID {
            if let existingUID = result.lastSyncedUID {
                result.lastSyncedUID = max(existingUID, incomingUID)
            } else {
                result.lastSyncedUID = incomingUID
            }
        }
        if let incomingPassUID = incoming.lastSyncedPassUID {
            if let existingPassUID = result.lastSyncedPassUID {
                result.lastSyncedPassUID = max(existingPassUID, incomingPassUID)
            } else {
                result.lastSyncedPassUID = incomingPassUID
            }
        }
        if result.imapUIDValidity == nil {
            result.imapUIDValidity = incoming.imapUIDValidity
        }
        if result.passImapUIDValidity == nil {
            result.passImapUIDValidity = incoming.passImapUIDValidity
        }

        var failed = Set(result.pendingFailedUIDs ?? [])
        failed.formUnion(incoming.pendingFailedUIDs ?? [])
        result.pendingFailedUIDs = failed.isEmpty ? nil : Array(failed).sorted()

        var failedPasses = Set(result.pendingFailedPassUIDs ?? [])
        failedPasses.formUnion(incoming.pendingFailedPassUIDs ?? [])
        result.pendingFailedPassUIDs = failedPasses.isEmpty ? nil : Array(failedPasses).sorted()
        return result
    }
}

extension Array where Element == UserProfile {
    var primary: UserProfile? {
        UserProfile.primary(from: self)
    }
}
