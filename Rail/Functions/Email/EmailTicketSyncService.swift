import Foundation
import SwiftData
import WidgetKit

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
    let newTicketsCount: Int
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

        var updatedEmails = profile.emails
        let sampleIDs = Set(updatedEmails[emailIndex].content.filter(\.isSampleTicket).map(\.id))
        if !sampleIDs.isEmpty {
            updatedEmails[emailIndex].content.removeAll { $0.isSampleTicket }
            profile.emails = updatedEmails
            try deleteTrains(linkedTo: sampleIDs, modelContext: modelContext)
            try modelContext.save()
        }

        // Full scan only on first sync (or after a parser upgrade). Refresh is incremental.
        let needsFullScan = reloadAll || updatedEmails[emailIndex].needsFullMailboxScan
        if needsFullScan {
            updatedEmails = profile.emails
            updatedEmails[emailIndex].lastSyncedUID = nil
            updatedEmails[emailIndex].pendingFailedUIDs = nil
            
            // If it's an explicit reloadAll, we still fetch all emails again, 
            // but we keep existing tickets so we don't delete saved trains.

            profile.emails = updatedEmails
            try modelContext.save()
        }

        let accountSnapshot = profile.emails[emailIndex]
        progress?(progressValue(account: accountSnapshot.email, stage: .searching))
        let fetchResult = try await EmailTrainFetcher(account: accountSnapshot).fetchEmails(
            afterUID: needsFullScan ? nil : accountSnapshot.lastSyncedUID,
            expectedUIDValidity: needsFullScan ? nil : accountSnapshot.imapUIDValidity,
            retryUIDs: needsFullScan ? [] : (accountSnapshot.pendingFailedUIDs ?? [])
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
                    detailsCompleted: 0,
                    newTicketsCount: 0
                )
            )
        }
        try Task.checkCancellation()
        let (pending, newCount) = try saveFetchedEmails(
            fetchResult,
            emailIndex: emailIndex,
            profile: profile,
            modelContext: modelContext
        )
        progress?(
            EmailTicketSyncProgress(
                accountEmail: account.email,
                stage: .finished,
                emailsFound: fetchResult.foundCount,
                emailsDownloaded: fetchResult.emails.count,
                emailsSkipped: fetchResult.failedUIDs.count,
                latestWarning: nil,
                detailsTotal: pending.count,
                detailsCompleted: pending.count,
                newTicketsCount: newCount
            )
        )
        return EmailAccountSyncResult(warnings: fetchResult.warnings)
    }

    static func tickets(from profile: UserProfile) -> [(account: Emails, ticket: EmailContent)] {
        profile.emails.flatMap { account in
            account.content
                .filter { !$0.isSampleTicket }
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
    ) throws -> ([EmailContent], Int) {
        var updatedEmails = profile.emails
        var updatedAccount = updatedEmails[emailIndex]

        if result.didResetUIDValidity {
            updatedAccount.content = []
        }

        var newCount = 0
        for item in result.emails {
            if let index = updatedAccount.content.firstIndex(where: { $0.imapUID == item.imapUID }) {
                applyParsedJourney(from: item, to: &updatedAccount.content[index])
            } else if let index = updatedAccount.content.firstIndex(where: {
                CheckInLink.extractID(from: $0.link) == item.checkInID
            }) {
                applyParsedJourney(from: item, to: &updatedAccount.content[index])
                updatedAccount.content[index].imapUID = item.imapUID
            } else {
                updatedAccount.content.append(emailContent(from: item))
                newCount += 1
            }
        }
        updatedAccount.lastSyncedUID = result.highestUID
        updatedAccount.pendingFailedUIDs = result.failedUIDs
        updatedAccount.syncGenerator = Emails.currentSyncGenerator
        if let uidValidity = result.uidValidity {
            updatedAccount.imapUIDValidity = uidValidity
        }

        updatedEmails[emailIndex] = updatedAccount
        profile.emails = updatedEmails
        try modelContext.save()

        return (profile.emails[emailIndex].content.filter(\.shouldFetchCheckInDetails), newCount)
    }

    private static func emailContent(from item: FetchedEmail) -> EmailContent {
        EmailContent(
            imapUID: item.imapUID,
            date: item.date,
            link: item.checkInID,
            departureDate: item.departureDate,
            arrivalDate: item.arrivalDate,
            trainNumber: item.trainNumber,
            departureStation: item.departureStation,
            arrivalStation: item.arrivalStation,
            price: item.price
        )
    }

    private static func applyParsedJourney(from item: FetchedEmail, to ticket: inout EmailContent) {
        ticket.date = item.date
        ticket.link = item.checkInID
        // Always restore timed departure/arrival from the email body when available.
        // Prefer email times over midnight-only values left by the check-in scraper.
        if let departureDate = item.departureDate,
           ticket.departureDate == nil || isMidnightOnly(ticket.departureDate) || !isMidnightOnly(departureDate) {
            ticket.departureDate = departureDate
        }
        if let arrivalDate = item.arrivalDate {
            ticket.arrivalDate = arrivalDate
        }
        if !item.trainNumber.isEmpty {
            ticket.trainNumber = item.trainNumber
        }
        if !item.departureStation.isEmpty {
            ticket.departureStation = item.departureStation
        }
        if !item.arrivalStation.isEmpty {
            ticket.arrivalStation = item.arrivalStation
        }
        if item.price != "Unknown" {
            ticket.price = item.price
        }
    }

    @MainActor
    static func fetchAndSaveTicketDetails(
        for ticketID: UUID,
        checkInID: String,
        emailIndex: Int,
        profile: UserProfile,
        modelContext: ModelContext
    ) async throws {
        guard !checkInID.isEmpty else { return }

        guard profile.emails.indices.contains(emailIndex) else { return }
        let account = profile.emails[emailIndex]
        guard let ticketIndex = account.content.firstIndex(where: { $0.id == ticketID }) else { return }
              
        let uid = account.content[ticketIndex].imapUID
        var fetchedDetails: EmailContent?
        
        // 1. Try extracting details from a PDF attachment if available
        let fetcher = EmailTrainFetcher(account: account)
        if let pdfs = try? await fetcher.fetchPDFs(forUID: uid),
           let firstPDF = pdfs.first {
            let passengers = PDFTicketParser.parse(pdfData: firstPDF)
            if !passengers.isEmpty && passengers.allSatisfy({ !$0.qrcode.isEmpty }) {
                fetchedDetails = account.content[ticketIndex]
                fetchedDetails?.passengers = passengers
                print("[PDFParser] Successfully extracted ticket details from PDF for \(uid)")
            }
        }
        
        // 2. Fallback to scraping the check-in web link
        if fetchedDetails == nil {
            print("[PDFParser] Falling back to check-in scraper for \(uid)")
            fetchedDetails = try await fetchTicketDetails(checkInID: checkInID)
        }
        
        guard let details = fetchedDetails else { return }
        try Task.checkCancellation()

        var updatedEmails = profile.emails
        updatedEmails[emailIndex].content[ticketIndex].link = checkInID
        if !details.trainNumber.isEmpty {
            updatedEmails[emailIndex].content[ticketIndex].trainNumber = details.trainNumber
        }
        if !details.departureStation.isEmpty {
            updatedEmails[emailIndex].content[ticketIndex].departureStation = details.departureStation
            updatedEmails[emailIndex].content[ticketIndex].arrivalStation = details.arrivalStation
        }
        updatedEmails[emailIndex].content[ticketIndex].passengers = details.passengers
        
        let currentDeparture = updatedEmails[emailIndex].content[ticketIndex].departureDate
        if currentDeparture == nil || isMidnightOnly(currentDeparture) {
            if let scraped = details.departureDate, !isMidnightOnly(scraped) || currentDeparture == nil {
                updatedEmails[emailIndex].content[ticketIndex].departureDate = scraped
            }
        }
        
        updatedEmails[emailIndex].content[ticketIndex].detailsFetchedAt = .now
        updatedEmails[emailIndex].content[ticketIndex].detailsError = nil
        profile.emails = updatedEmails
        try modelContext.save()
    }

    private static func isMidnightOnly(_ date: Date?) -> Bool {
        guard let date else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar.component(.hour, from: date) == 0
            && calendar.component(.minute, from: date) == 0
    }

    @MainActor
    private static func deleteTrains(linkedTo ticketIDs: Set<UUID>, modelContext: ModelContext) throws {
        guard !ticketIDs.isEmpty else { return }
        let trains = try modelContext.fetch(FetchDescriptor<Train>())
        for train in trains where train.sourceEmailTicketID.map(ticketIDs.contains) == true {
            let trainID = train.id
            let stops = try modelContext.fetch(FetchDescriptor<Stop>(predicate: #Predicate { $0.id == trainID }))
            let seats = try modelContext.fetch(FetchDescriptor<Seat>(predicate: #Predicate { $0.trainID == trainID }))
            stops.forEach(modelContext.delete)
            seats.forEach(modelContext.delete)
            modelContext.delete(train)
        }
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
            detailsCompleted: 0,
            newTicketsCount: 0
        )
    }
}
