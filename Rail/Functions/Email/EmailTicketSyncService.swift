import Foundation
import SwiftData

enum EmailTicketSyncStage: Sendable {
    case searching
    case downloading
    case fetchingDetails
    case finished
}

struct EmailTicketSyncProgress: Sendable {
    let accountEmail: String
    let stage: EmailTicketSyncStage
    let emailsFound: Int
    let emailsDownloaded: Int
    let emailsSkipped: Int
    let latestWarning: String?
    let detailsTotal: Int
    let detailsCompleted: Int
}

struct EmailAccountSyncResult: Sendable {
    let warnings: [String]
}

enum EmailTicketSyncService {
    @MainActor
    static func syncAccount(
        accountID: UUID,
        profile: UserProfile,
        modelContext: ModelContext,
        reloadAll: Bool = false,
        progress: ((EmailTicketSyncProgress) -> Void)? = nil
    ) async throws -> EmailAccountSyncResult {
        guard let emailIndex = profile.emails.firstIndex(where: { $0.id == accountID }) else {
            return EmailAccountSyncResult(warnings: [])
        }
        let account = profile.emails[emailIndex]

        if reloadAll {
            var updatedEmails = profile.emails
            updatedEmails[emailIndex].content = []
            profile.emails = updatedEmails
            try modelContext.save()
        }

        progress?(progressValue(account: account.email, stage: .searching))
        let fetchResult = try await EmailFetcher(account: account).fetchEmails(
            afterUID: reloadAll ? nil : account.lastSyncedUID,
            expectedUIDValidity: reloadAll ? nil : account.imapUIDValidity,
            retryUIDs: reloadAll ? [] : (account.pendingFailedUIDs ?? [])
        ) { value in
            progress?(
                EmailTicketSyncProgress(
                    accountEmail: account.email,
                    stage: .downloading,
                    emailsFound: value.found,
                    emailsDownloaded: value.processed,
                    emailsSkipped: value.skipped,
                    latestWarning: value.latestWarning,
                    detailsTotal: 0,
                    detailsCompleted: 0
                )
            )
        }
        try Task.checkCancellation()
        let pending = try saveFetchedEmails(
            fetchResult,
            emailIndex: emailIndex,
            profile: profile,
            modelContext: modelContext
        )
        let warnings = await fetchDetails(
            for: pending,
            emailIndex: emailIndex,
            accountEmail: account.email,
            emailsFound: fetchResult.foundCount,
            emailsDownloaded: fetchResult.foundCount,
            emailsSkipped: fetchResult.failedUIDs.count,
            profile: profile,
            modelContext: modelContext,
            progress: progress
        )
        progress?(
            EmailTicketSyncProgress(
                accountEmail: account.email,
                stage: .finished,
                emailsFound: fetchResult.foundCount,
                emailsDownloaded: fetchResult.foundCount,
                emailsSkipped: fetchResult.failedUIDs.count,
                latestWarning: nil,
                detailsTotal: pending.count,
                detailsCompleted: pending.count
            )
        )
        return EmailAccountSyncResult(warnings: fetchResult.warnings + warnings)
    }

    static func tickets(from profile: UserProfile) -> [(account: Emails, ticket: EmailContent)] {
        profile.emails.flatMap { account in
            account.content
                .filter { CheckInLink.extractID(from: $0.link) != nil }
                .map { (account, $0) }
        }
        .sorted {
            if $0.ticket.isImportEligible != $1.ticket.isImportEligible {
                return $0.ticket.isImportEligible
            }
            let lhs = $0.ticket.departureDate ?? $0.ticket.date
            let rhs = $1.ticket.departureDate ?? $1.ticket.date
            return $0.ticket.isImportEligible ? lhs < rhs : lhs > rhs
        }
    }

    @MainActor
    private static func saveFetchedEmails(
        _ result: EmailFetchResult,
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) throws -> [EmailContent] {
        var updatedEmails = profile.emails
        var updatedAccount = updatedEmails[emailIndex]

        if result.didResetUIDValidity {
            updatedAccount.content = []
        }

        for item in result.emails {
            if let index = updatedAccount.content.firstIndex(where: { $0.imapUID == item.imapUID }) {
                applyParsedJourney(from: item, to: &updatedAccount.content[index])
            } else {
                updatedAccount.content.append(emailContent(from: item))
            }
        }
        updatedAccount.lastSyncedUID = result.highestUID
        updatedAccount.pendingFailedUIDs = result.failedUIDs
        if let uidValidity = result.uidValidity {
            updatedAccount.imapUIDValidity = uidValidity
        }

        updatedEmails[emailIndex] = updatedAccount
        profile.emails = updatedEmails
        try modelContext.save()

        return profile.emails[emailIndex].content.filter { ticket in
            ticket.isImportEligible
                && CheckInLink.extractID(from: ticket.link) != nil
                && !ticket.hasLoadedDetails
        }
    }

    @MainActor
    private static func fetchDetails(
        for pending: [EmailContent],
        emailIndex: Int,
        accountEmail: String,
        emailsFound: Int,
        emailsDownloaded: Int,
        emailsSkipped: Int,
        profile: UserProfile,
        modelContext: ModelContext,
        progress: ((EmailTicketSyncProgress) -> Void)?
    ) async -> [String] {
        var warnings: [String] = []
        for (index, ticket) in pending.enumerated() {
            guard !Task.isCancelled else { break }
            guard !ticket.hasLoadedDetails else { continue }
            progress?(
                EmailTicketSyncProgress(
                    accountEmail: accountEmail,
                    stage: .fetchingDetails,
                    emailsFound: emailsFound,
                    emailsDownloaded: emailsDownloaded,
                    emailsSkipped: emailsSkipped,
                    latestWarning: nil,
                    detailsTotal: pending.count,
                    detailsCompleted: index
                )
            )
            do {
                try await fetchAndSaveTicketDetails(
                    for: ticket.id,
                    checkInID: ticket.link,
                    emailIndex: emailIndex,
                    profile: profile,
                    modelContext: modelContext
                )
            } catch {
                let message = error.localizedDescription
                warnings.append(message)
                saveDetailError(
                    message,
                    ticketID: ticket.id,
                    emailIndex: emailIndex,
                    profile: profile,
                    modelContext: modelContext
                )
            }
        }
        return warnings
    }

    private static func emailContent(from item: FetchedEmail) -> EmailContent {
        EmailContent(
            imapUID: item.imapUID,
            date: item.date,
            link: item.checkInID,
            departureDate: item.departureDate,
            trainNumber: item.trainNumber,
            departureStation: item.departureStation,
            arrivalStation: item.arrivalStation
        )
    }

    private static func applyParsedJourney(from item: FetchedEmail, to ticket: inout EmailContent) {
        ticket.date = item.date
        ticket.link = item.checkInID
        ticket.departureDate = item.departureDate

        guard !ticket.hasLoadedDetails else { return }

        ticket.trainNumber = item.trainNumber
        ticket.departureStation = item.departureStation
        ticket.arrivalStation = item.arrivalStation
    }

    @MainActor
    private static func fetchAndSaveTicketDetails(
        for ticketID: UUID,
        checkInID: String,
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) async throws {
        guard !checkInID.isEmpty else { return }

        let details = try await fetchTicketDetails(checkInID: checkInID)
        try Task.checkCancellation()

        guard let ticketIndex = profile.emails[emailIndex].content.firstIndex(where: { $0.id == ticketID }) else { return }

        var updatedEmails = profile.emails
        updatedEmails[emailIndex].content[ticketIndex].link = checkInID
        updatedEmails[emailIndex].content[ticketIndex].trainNumber = details.trainNumber
        updatedEmails[emailIndex].content[ticketIndex].departureStation = details.departureStation
        updatedEmails[emailIndex].content[ticketIndex].arrivalStation = details.arrivalStation
        updatedEmails[emailIndex].content[ticketIndex].passengers = details.passengers
        if updatedEmails[emailIndex].content[ticketIndex].departureDate == nil {
            updatedEmails[emailIndex].content[ticketIndex].departureDate = details.departureDate
        }
        updatedEmails[emailIndex].content[ticketIndex].detailsFetchedAt = .now
        updatedEmails[emailIndex].content[ticketIndex].detailsError = nil
        profile.emails = updatedEmails
        try modelContext.save()
    }

    @MainActor
    private static func saveDetailError(
        _ message: String,
        ticketID: UUID,
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) {
        guard profile.emails.indices.contains(emailIndex),
              let ticketIndex = profile.emails[emailIndex].content.firstIndex(where: { $0.id == ticketID }) else { return }
        var updatedEmails = profile.emails
        updatedEmails[emailIndex].content[ticketIndex].detailsError = message
        profile.emails = updatedEmails
        try? modelContext.save()
    }

    private static func progressValue(
        account: String,
        stage: EmailTicketSyncStage
    ) -> EmailTicketSyncProgress {
        EmailTicketSyncProgress(
            accountEmail: account,
            stage: stage,
            emailsFound: 0,
            emailsDownloaded: 0,
            emailsSkipped: 0,
            latestWarning: nil,
            detailsTotal: 0,
            detailsCompleted: 0
        )
    }
}
