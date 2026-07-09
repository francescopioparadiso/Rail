import Foundation
import SwiftData

enum EmailTicketSyncService {
    @MainActor
    static func syncAccount(
        accountID: UUID,
        profile: UserProfile,
        modelContext: ModelContext,
        reloadAll: Bool = false
    ) async throws {
        guard let emailIndex = profile.emails.firstIndex(where: { $0.id == accountID }) else { return }
        let account = profile.emails[emailIndex]

        if reloadAll {
            var updatedEmails = profile.emails
            updatedEmails[emailIndex].content = []
            profile.emails = updatedEmails
            try modelContext.save()
        }

        let knownIMAPUIDs: Set<String> = reloadAll ? [] : Set(
            profile.emails[emailIndex].content
                .filter { CheckInLink.extractID(from: $0.link) != nil }
                .map(\.imapUID)
        )

        let fetched = try await EmailFetcher(account: account).fetchEmails(knownIMAPUIDs: knownIMAPUIDs)
        let pending = try saveFetchedEmails(fetched, emailIndex: emailIndex, profile: profile, modelContext: modelContext)
        await fetchDetails(for: pending, emailIndex: emailIndex, profile: profile, modelContext: modelContext)
    }

    @MainActor
    static func syncAllAccounts(profile: UserProfile, modelContext: ModelContext) async {
        for account in profile.emails {
            do {
                try await syncAccount(accountID: account.id, profile: profile, modelContext: modelContext)
            } catch {
                print("Failed to sync email account \(account.email):", error.localizedDescription)
            }
        }
    }

    static func importableTickets(from profile: UserProfile) -> [(account: Emails, ticket: EmailContent)] {
        profile.emails.flatMap { account in
            account.content
                .filter { $0.isUpcoming && !$0.trainNumber.isEmpty }
                .map { (account, $0) }
        }
        .sorted {
            ($0.ticket.departureDate ?? $0.ticket.date) < ($1.ticket.departureDate ?? $1.ticket.date)
        }
    }

    @MainActor
    private static func saveFetchedEmails(
        _ fetched: [FetchedEmail],
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) throws -> [FetchedEmail] {
        var updatedEmails = profile.emails
        var updatedAccount = updatedEmails[emailIndex]

        for item in fetched {
            if let index = updatedAccount.content.firstIndex(where: { $0.imapUID == item.imapUID }) {
                applyParsedJourney(from: item, to: &updatedAccount.content[index])
            } else {
                updatedAccount.content.append(emailContent(from: item))
            }
        }

        updatedEmails[emailIndex] = updatedAccount
        profile.emails = updatedEmails
        try modelContext.save()

        return fetched.filter { item in
            guard item.shouldFetchDetails else { return false }
            guard let ticket = profile.emails[emailIndex].content.first(where: { $0.imapUID == item.imapUID }) else { return false }
            return !ticket.hasLoadedDetails
        }
    }

    @MainActor
    private static func fetchDetails(
        for pending: [FetchedEmail],
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) async {
        for item in pending {
            guard let ticket = profile.emails[emailIndex].content.first(where: { $0.imapUID == item.imapUID }),
                  !ticket.hasLoadedDetails else { continue }

            do {
                try await fetchAndSaveTicketDetails(
                    for: ticket.id,
                    checkInID: item.checkInID,
                    emailIndex: emailIndex,
                    profile: profile,
                    modelContext: modelContext
                )
            } catch {
                print("Failed to scrape ticket \(item.checkInID):", error.localizedDescription)
            }
        }
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

        guard let ticketIndex = profile.emails[emailIndex].content.firstIndex(where: { $0.id == ticketID }) else { return }

        var updatedEmails = profile.emails
        updatedEmails[emailIndex].content[ticketIndex].link = checkInID
        updatedEmails[emailIndex].content[ticketIndex].trainNumber = details.trainNumber
        updatedEmails[emailIndex].content[ticketIndex].departureStation = details.departureStation
        updatedEmails[emailIndex].content[ticketIndex].arrivalStation = details.arrivalStation
        updatedEmails[emailIndex].content[ticketIndex].passengers = details.passengers
        profile.emails = updatedEmails
        try modelContext.save()
    }
}
