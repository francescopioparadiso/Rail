import Foundation
import SwiftData
import WidgetKit

enum EmailPassSyncStage: Sendable {
    case searching
    case downloading
    case finished
}

struct EmailPassSyncProgress: Sendable {
    let accountEmail: String
    let stage: EmailPassSyncStage
    let emailsFound: Int
    let emailsDownloaded: Int
    let emailsSkipped: Int
    let latestWarning: String?
}

struct EmailPassSyncResult: Sendable {
    let warnings: [String]
}

enum EmailPassSyncService {
    @MainActor
    static func syncAccount(
        accountID: UUID,
        profile: UserProfile,
        modelContext: ModelContext,
        reloadAll: Bool = false,
        progress: ((EmailPassSyncProgress) -> Void)? = nil
    ) async throws -> EmailPassSyncResult {
        guard let emailIndex = profile.emails.firstIndex(where: { $0.id == accountID }) else {
            return EmailPassSyncResult(warnings: [])
        }

        var updatedEmails = profile.emails
        let needsFullScan = reloadAll || updatedEmails[emailIndex].needsFullPassMailboxScan
        if needsFullScan {
            updatedEmails[emailIndex].lastSyncedPassUID = nil
            updatedEmails[emailIndex].pendingFailedPassUIDs = nil
            updatedEmails[emailIndex].passes = []
            profile.emails = updatedEmails
            try modelContext.save()
        }

        let accountSnapshot = profile.emails[emailIndex]
        progress?(
            EmailPassSyncProgress(
                accountEmail: accountSnapshot.email,
                stage: .searching,
                emailsFound: 0,
                emailsDownloaded: 0,
                emailsSkipped: 0,
                latestWarning: nil
            )
        )

        let fetchResult = try await EmailPassFetcher(account: accountSnapshot).fetchPassEmails(
            afterUID: needsFullScan ? nil : accountSnapshot.lastSyncedPassUID,
            expectedUIDValidity: needsFullScan ? nil : accountSnapshot.passImapUIDValidity,
            retryUIDs: needsFullScan ? [] : (accountSnapshot.pendingFailedPassUIDs ?? [])
        ) { value in
            progress?(
                EmailPassSyncProgress(
                    accountEmail: accountSnapshot.email,
                    stage: .downloading,
                    emailsFound: value.found,
                    emailsDownloaded: value.processed,
                    emailsSkipped: value.skipped,
                    latestWarning: value.latestWarning
                )
            )
        }
        try Task.checkCancellation()
        try saveFetchedPasses(
            fetchResult,
            emailIndex: emailIndex,
            profile: profile,
            modelContext: modelContext
        )

        progress?(
            EmailPassSyncProgress(
                accountEmail: accountSnapshot.email,
                stage: .finished,
                emailsFound: fetchResult.foundCount,
                emailsDownloaded: fetchResult.foundCount,
                emailsSkipped: fetchResult.failedUIDs.count,
                latestWarning: nil
            )
        )
        return EmailPassSyncResult(warnings: fetchResult.warnings)
    }

    static func passes(from profile: UserProfile) -> [(account: Emails, pass: EmailPassContent)] {
        profile.emails.flatMap { account in
            account.passes.map { (account, $0) }
        }
        .sorted {
            if $0.pass.startDate != $1.pass.startDate {
                return $0.pass.startDate > $1.pass.startDate
            }
            return $0.pass.endDate > $1.pass.endDate
        }
    }

    @MainActor
    @discardableResult
    static func savePass(
        _ emailPass: EmailPassContent,
        modelContext: ModelContext,
        existingPasses: [Pass]
    ) -> Pass? {
        let fingerprintStart = Calendar.current.startOfDay(for: emailPass.startDate)
        let fingerprintEnd = Calendar.current.startOfDay(for: emailPass.endDate)

        // If a previous import saved a default/incorrect start date for the same pass,
        // update that record instead of inserting a duplicate.
        if let existingIndex = existingPasses.firstIndex(where: {
            Calendar.current.isDate($0.expiry_date, inSameDayAs: fingerprintEnd)
                && $0.name.caseInsensitiveCompare(emailPass.name) == .orderedSame
        }) {
            let pass = existingPasses[existingIndex]
            pass.start_date = emailPass.startDate
            pass.expiry_date = emailPass.endDate
            pass.name = emailPass.name
            pass.price = emailPass.price
            pass.image = emailPass.qrcode.isEmpty ? pass.image : emailPass.qrcode
            if let pdf = PassPDFStore.load(emailPass.pdfFilename) {
                pass.pdf = pdf
                PassPDFStore.discard(emailPass.pdfFilename)
            }
            try? modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
            return pass
        }

        // Already stored under the same period: top up anything the earlier
        // import couldn't parse rather than walking away or duplicating.
        if let stored = existingPasses.first(where: {
            Calendar.current.isDate($0.start_date, inSameDayAs: fingerprintStart)
                && Calendar.current.isDate($0.expiry_date, inSameDayAs: fingerprintEnd)
        }) {
            fillInMissingDetails(of: stored, from: emailPass, modelContext: modelContext)
            return stored
        }

        let pass = Pass(
            id: UUID(),
            name: emailPass.name,
            start_date: emailPass.startDate,
            expiry_date: emailPass.endDate,
            is_principal: false,
            price: emailPass.price,
            image: emailPass.qrcode.isEmpty ? nil : emailPass.qrcode,
            pdf: PassPDFStore.load(emailPass.pdfFilename)
        )
        modelContext.insert(pass)
        PassPDFStore.discard(emailPass.pdfFilename)
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        return pass
    }

    /// Backfills a stored pass when a later sync parses something the first one
    /// missed — a price the old regex couldn't read, or a PDF added since.
    static func fillInMissingDetails(
        of pass: Pass,
        from emailPass: EmailPassContent,
        modelContext: ModelContext
    ) {
        var changed = false

        let parsedPrice = emailPass.price.trimmingCharacters(in: .whitespaces)
        let storedPrice = pass.price.trimmingCharacters(in: .whitespaces)
        if !parsedPrice.isEmpty, parsedPrice.lowercased() != "unknown", storedPrice != parsedPrice {
            pass.price = parsedPrice
            changed = true
        }

        if (pass.pdf?.isEmpty ?? true), let pdf = PassPDFStore.load(emailPass.pdfFilename) {
            pass.pdf = pdf
            PassPDFStore.discard(emailPass.pdfFilename)
            changed = true
        }

        if (pass.image?.isEmpty ?? true), !emailPass.qrcode.isEmpty {
            pass.image = emailPass.qrcode
            changed = true
        }

        if changed {
            try? modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    private static func saveFetchedPasses(
        _ fetchResult: EmailPassFetchResult,
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) throws {
        var updatedEmails = profile.emails
        var passes = updatedEmails[emailIndex].passes

        for fetched in fetchResult.passes {
            let content = EmailPassContent(
                imapUID: fetched.imapUID,
                date: fetched.date,
                name: fetched.name,
                startDate: fetched.startDate,
                endDate: fetched.endDate,
                price: fetched.price,
                qrcode: fetched.qrcode,
                pdfFilename: fetched.pdfFilename
            )
            if let index = passes.firstIndex(where: {
                $0.imapUID == content.imapUID || $0.fingerprint == content.fingerprint
            }) {
                var replacement = content
                if replacement.pdfFilename == nil {
                    // a re-scan that didn't re-extract the PDF must not drop the
                    // one already staged, or the pass loses its document
                    replacement.pdfFilename = passes[index].pdfFilename
                } else if passes[index].pdfFilename != replacement.pdfFilename {
                    PassPDFStore.discard(passes[index].pdfFilename)
                }
                passes[index] = replacement
            } else {
                passes.append(content)
            }
        }

        updatedEmails[emailIndex].passes = passes
        if let highest = fetchResult.highestUID {
            updatedEmails[emailIndex].lastSyncedPassUID = highest
        }
        if let validity = fetchResult.uidValidity {
            updatedEmails[emailIndex].passImapUIDValidity = validity
        }
        updatedEmails[emailIndex].pendingFailedPassUIDs =
            fetchResult.failedUIDs.isEmpty ? nil : fetchResult.failedUIDs
        updatedEmails[emailIndex].passSyncGenerator = Emails.currentPassSyncGenerator
        profile.emails = updatedEmails
        try modelContext.save()

        // Passes imported before the parser could read their price (or before
        // PDFs were stored) are refreshed here, so a sync is enough — the user
        // shouldn't have to delete and re-add them.
        let stored = (try? modelContext.fetch(FetchDescriptor<Pass>())) ?? []
        guard !stored.isEmpty else { return }
        for content in passes {
            let start = Calendar.current.startOfDay(for: content.startDate)
            let end = Calendar.current.startOfDay(for: content.endDate)
            guard let match = stored.first(where: {
                Calendar.current.isDate($0.start_date, inSameDayAs: start)
                    && Calendar.current.isDate($0.expiry_date, inSameDayAs: end)
            }) else { continue }
            fillInMissingDetails(of: match, from: content, modelContext: modelContext)
        }
    }
}
