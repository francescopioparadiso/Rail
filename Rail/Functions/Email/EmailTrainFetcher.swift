import Foundation

struct FetchedEmail: Sendable {
    let imapUID: String
    let checkInID: String
    let date: Date
    let departureDate: Date?
    let arrivalDate: Date?
    let trainNumber: String
    let departureStation: String
    let arrivalStation: String
    let price: String
    /// "trenitalia", whose `checkInID` is the check-in link's id, or "italo", whose
    /// `checkInID` is the ticket code.
    var provider: String = "trenitalia"
    /// Which journey of the email: 1 for the return of an Italo round trip.
    var leg: Int = 0
}

/// What an Italo email's attachments add to the ticket.
struct ItaloTicketDetails: Sendable {
    let passengerName: String
    let carriage: Int
    let seat: String
    let price: String?
    /// The barcode image from the email, empty if it carried none.
    let barcode: Data
}

struct EmailFetchProgress: Sendable {
    let found: Int
    let processed: Int
    let skipped: Int
    let latestWarning: String?
}

struct EmailFetchResult: Sendable {
    let emails: [FetchedEmail]
    /// Emails that could not be read at all. Worth another go next sync.
    let failedUIDs: [UInt64]
    /// Emails that were read in full and are not tickets. Reading them again would
    /// reach the same verdict, so they are remembered as checked and left alone.
    let rejectedUIDs: [UInt64]
    let warnings: [String]
    let highestUID: UInt64?
    let uidValidity: UInt64?
    let didResetUIDValidity: Bool
    let foundCount: Int
}

enum EmailFetchError: Error, LocalizedError {
    case connectionFailed
    case authFailed
    case inboxFailed
    case searchFailed
    case fetchFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return String(localized: "Could not connect to the mail server.")
        case .authFailed:
            return String(localized: "Email login failed. Check your address and app password.")
        case .inboxFailed:
            return String(localized: "Could not open the inbox.")
        case .searchFailed:
            return String(localized: "Could not search for Trenitalia emails.")
        case .fetchFailed:
            return String(localized: "Could not download an email message.")
        case .timedOut:
            return String(localized: "The email server took too long to respond.")
        }
    }
}

actor EmailTrainFetcher {

    // MARK: - Properties

    // MARK: - Properties

    private let session: IMAPSession

    init(account: Emails) {
        self.session = IMAPSession(account: account)
    }

    // MARK: - Methods

    private func fetchCommand(for uid: String) -> String {
        // Fetch the full message, exactly like the Python script's `(BODY.PEEK[])` — no
        // partial byte range. A partial range risks truncating before the journey details
        // on larger messages (e.g. ones with inline images).
        // EmailBodyDecoder then handles multipart/base64 decoding.
        "UID FETCH \(uid) (BODY.PEEK[])"
    }

    /// How many emails each `UID FETCH` asks for at once.
    private static let batchSize = 20

    /// How much of each email a scan downloads first. The journey and the check-in
    /// link live in the text, which comes before the PDF — the bulk of the message —
    /// so this is usually all of it that is needed.
    private static let previewBytes = 131_072

    private static let previewItems = "BODY.PEEK[]<0.\(previewBytes)>"

    /// Whether a preview stopped short of the text: it was cut, and before reaching
    /// any attachment — past one, the text parts ahead of it are already whole.
    private static func previewMayMissText(_ raw: String) -> Bool {
        guard (IMAPSession.firstLiteralSize(in: raw) ?? 0) >= previewBytes else { return false }
        let lower = raw.lowercased()
        return !lower.contains("content-disposition: attachment")
            && !lower.contains("content-type: application/")
    }

    /// The previews of the next batch of emails, by UID. Empty if the batch failed,
    /// with the connection reopened so each email is then fetched on its own.
    private func prefetchPreviews(_ uids: [String], folder: String) async throws -> [String: String] {
        do {
            return try await session.fetchMessages(uids: uids, items: Self.previewItems)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            session.close()
            _ = try? await session.openMailbox(folder: folder)
            return [:]
        }
    }

    private func extractCheckInID(from body: String) -> String? {
        let clean = EmailBodyDecoder.unescapeQuotedPrintable(body)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "%3F", with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: "%3D", with: "=", options: .caseInsensitive)
            .replacingOccurrences(of: "%26", with: "&", options: .caseInsensitive)

        let patterns = [
            #"self-check-in[^\"'<>\s]*[?&]id=([A-Za-z0-9+/_%=-]+)"#,
            #"selfcheckin[^\"'<>\s]*[?&]id=([A-Za-z0-9+/_%=-]+)"#,
            #"lefrecce\.it[^\"'<>\s]*[?&]id=([A-Za-z0-9+/_%=-]{16,})"#,
            #"[?&]id=([A-Za-z0-9+/_%=-]{20,})[^\"'<>\s]*lang="#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(clean.startIndex..., in: clean)
            guard let match = regex.firstMatch(in: clean, range: range),
                  let idRange = Range(match.range(at: 1), in: clean),
                  let id = CheckInLink.extractID(from: String(clean[idRange])) else { continue }
            return id
        }

        return nil
    }

    private func parseEmail(_ raw: String, uid: String) -> [FetchedEmail] {
        let content = IMAPResponse.messageContent(from: raw)
        let searchable = content ?? raw
        // the whole response only adds to the message itself when that couldn't be cut out
        let decoded = content == nil
            ? EmailBodyDecoder.decode(body: raw, headers: raw).text
            : EmailBodyDecoder.decode(body: searchable, headers: searchable).text

        print("[EMAIL-DEBUG] UID \(uid): raw=\(raw.count) chars, searchable=\(searchable.count) chars, decoded=\(decoded.count) chars")
        let snippet = String(decoded.prefix(300)).replacingOccurrences(of: "\n", with: "⏎")
        print("[EMAIL-DEBUG] UID \(uid): decoded snippet: \(snippet)")

        let date = IMAPResponse.header("Date", in: searchable).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("Date", in: raw).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("DATE", in: searchable).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("DATE", in: raw).flatMap(IMAPResponse.parseDate)
            ?? .distantPast

        // Italo's confirmation holds the whole journey, so it has no check-in page to read
        let fromHeader = IMAPResponse.header("From", in: searchable) ?? IMAPResponse.header("From", in: raw)
        if fromHeader.map(ItaloEmailParser.isItaloSender) == true || ItaloEmailParser.looksLikeConfirmation(decoded) {
            return parseItaloEmail(decoded, uid: uid, date: date)
        }

        // Quick keyword filter like Python: skip if none of these keywords present
        let lower = decoded.lowercased()
        let hasPnr = lower.contains("pnr")
        let hasBarcode = lower.contains("barcode")
        let hasBiglietto = lower.contains("biglietto")
        let hasCheckin = lower.contains("self-check-in")
        guard hasPnr || hasBarcode || hasBiglietto || hasCheckin else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - no keywords (pnr=\(hasPnr), barcode=\(hasBarcode), biglietto=\(hasBiglietto), checkin=\(hasCheckin))")
            return []
        }
        print("[EMAIL-DEBUG] UID \(uid): keywords found (pnr=\(hasPnr), barcode=\(hasBarcode), biglietto=\(hasBiglietto), checkin=\(hasCheckin))")

        guard let from = IMAPResponse.header("From", in: searchable)
                ?? IMAPResponse.header("From", in: raw)
                ?? IMAPResponse.header("FROM", in: searchable)
                ?? IMAPResponse.header("FROM", in: raw) else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - no From header found")
            return []
        }

        let sender = from.firstIndex(of: "<").flatMap { s in
            from.firstIndex(of: ">").map { String(from[from.index(after: s)..<$0]).lowercased() }
        } ?? from.lowercased()
        print("[EMAIL-DEBUG] UID \(uid): sender=\(sender)")

        let isTrenitaliaSender =
            sender.contains("trenitalia.it")
            || sender.contains("lefrecce.it")
            || sender.contains("trenitalia")
            || sender.contains("lefrecce")
        let foundCheckInID = extractCheckInID(from: decoded)
        guard isTrenitaliaSender || foundCheckInID != nil else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - not trenitalia sender and no check-in ID")
            return []
        }

        // Second filter, after the body keywords and the sender: the check-in id is the
        // only way to reach a ticket's details, so an email without one is nothing this
        // app can act on. An Abbonamento confirmation arrives under the same
        // "Il Tuo Biglietto Trenitalia" subject and is separated from a real ticket
        // by exactly this — a ticket always carries the link.
        guard let checkInID = foundCheckInID else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - no check-in ID to fetch details with")
            return []
        }
        print("[EMAIL-DEBUG] UID \(uid): checkInID=\(checkInID.prefix(40))...")

        let journey = EmailJourneyParser.parse(from: decoded)

        print("[EMAIL-DEBUG] UID \(uid): PARSED ✅ train=\(journey?.trainNumber ?? "nil") dep=\(journey?.departureStation ?? "nil") arr=\(journey?.arrivalStation ?? "nil") price=\(journey?.price ?? "nil") date=\(date)")

        return [FetchedEmail(
            imapUID: uid,
            checkInID: checkInID,
            date: date,
            departureDate: journey?.departureDate,
            arrivalDate: journey?.arrivalDate,
            trainNumber: journey?.trainNumber ?? "",
            departureStation: journey?.departureStation ?? "",
            arrivalStation: journey?.arrivalStation ?? "",
            price: journey?.price ?? "Unknown"
        )]
    }

    private func parseItaloEmail(_ decoded: String, uid: String, date: Date) -> [FetchedEmail] {
        let journeys = ItaloEmailParser.parseAll(html: decoded, emailDate: date)
        if journeys.isEmpty {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - Italo email without a ticket")
        }
        return journeys.map { journey in
            FetchedEmail(
                imapUID: uid,
                checkInID: journey.code,
                date: date,
                departureDate: journey.departureDate,
                arrivalDate: journey.arrivalDate,
                trainNumber: journey.trainNumber,
                departureStation: journey.departureStation,
                arrivalStation: journey.arrivalStation,
                price: "Unknown",
                provider: "italo",
                leg: journey.leg
            )
        }
    }

    func verifyCredentials() async throws {
        try Task.checkCancellation()
        _ = try await session.openMailbox()
        session.close()
    }

    func fetchEmails(
        afterUID: UInt64?,
        expectedUIDValidity: UInt64?,
        retryUIDs: [UInt64],
        progress: (@MainActor @Sendable (EmailFetchProgress) -> Void)? = nil
    ) async throws -> EmailFetchResult {
        try Task.checkCancellation()
        let (inbox, openedFolder) = try await session.openPassMailbox()
        defer { session.close() }

        let currentUIDValidity = IMAPResponse.uidValidity(in: inbox)
        let didResetUIDValidity = expectedUIDValidity != nil
            && currentUIDValidity != nil
            && expectedUIDValidity != currentUIDValidity
        let effectiveLastUID = didResetUIDValidity ? nil : afterUID
        let uidConstraint: String
        if let effectiveLastUID, effectiveLastUID < UInt64.max {
            uidConstraint = "UID \(effectiveLastUID + 1):*"
        } else if effectiveLastUID == UInt64.max {
            uidConstraint = "UID \(UInt64.max):\(UInt64.max)"
        } else {
            uidConstraint = ""
        }

        // Keep searches cheap. Full BODY scans are unnecessary for Trenitalia senders.
        // We prioritize the most comprehensive search. If the IMAP server rejects OR, we fall back.
        let criteriaOptions = [
            #"FROM "webmaster@trenitalia.it" OR SUBJECT "Il tuo biglietto trenitalia" SUBJECT "your trenitalia ticket""#,
            #"FROM "webmaster@trenitalia.it" SUBJECT "biglietto trenitalia""#,
            #"FROM "webmaster@trenitalia.it" SUBJECT "trenitalia ticket""#
        ]
        var search = ""
        for criteria in criteriaOptions {
            let commandText = uidConstraint.isEmpty
                ? "UID SEARCH \(criteria)"
                : "UID SEARCH \(uidConstraint) \(criteria)"
            do {
                let response = try await session.command(commandText)
                if IMAPResponse.taggedSuccess(response) {
                    search = response
                    break
                }
            } catch {
                continue
            }
        }
        guard !search.isEmpty else { throw EmailFetchError.searchFailed }

        // Italo's purchase confirmations, which the Trenitalia search leaves out. A
        // failure here only means no Italo tickets this time, never a failed scan.
        // (a friend's forward or reply has the subject but not the sender)
        let italoCriteria = #"OR (FROM "italotreno.it" SUBJECT "Conferma") (SUBJECT "Italo" SUBJECT "Conferma")"#
        let italoSearch = try? await session.command(
            uidConstraint.isEmpty ? "UID SEARCH \(italoCriteria)" : "UID SEARCH \(uidConstraint) \(italoCriteria)"
        )
        let italoUIDs = italoSearch.flatMap { IMAPResponse.taggedSuccess($0) ? IMAPResponse.uids(in: $0) : nil } ?? []

        let newUIDs = Set(IMAPResponse.uids(in: search) + italoUIDs)
            .compactMap { uid in UInt64(uid).map { (raw: uid, numeric: $0) } }
            .filter { item in
                guard let effectiveLastUID else { return true }
                return item.numeric > effectiveLastUID
            }
            .sorted { $0.numeric < $1.numeric }
        let retryValues = didResetUIDValidity ? [] : retryUIDs
        var uidsByValue: [UInt64: (raw: String, numeric: UInt64)] = Dictionary(uniqueKeysWithValues: newUIDs.map { ($0.numeric, $0) })
        for uid in retryValues {
            uidsByValue[uid] = (raw: String(uid), numeric: uid)
        }
        let matchingUIDs = uidsByValue.values.sorted { $0.numeric < $1.numeric }
        await progress?(
            EmailFetchProgress(found: matchingUIDs.count, processed: 0, skipped: 0, latestWarning: nil)
        )

        var emails: [FetchedEmail] = []
        var failedUIDs: [UInt64] = []
        var rejectedUIDs: [UInt64] = []
        var warnings: [String] = []
        var previews: [String: String] = [:]
        for (index, uid) in matchingUIDs.enumerated() {
            try Task.checkCancellation()
            if index % Self.batchSize == 0 {
                let batch = matchingUIDs[index..<min(index + Self.batchSize, matchingUIDs.count)]
                previews = try await prefetchPreviews(batch.map(\.raw), folder: openedFolder)
            }
            var latestWarning: String?
            do {
                var parsed: [FetchedEmail] = []
                var needsFullMessage = true
                // a preview cut short of the text could have parsed on half a journey
                if let preview = previews[uid.raw], !Self.previewMayMissText(preview) {
                    parsed = parseEmail(preview, uid: uid.raw)
                    needsFullMessage = false
                }
                // the whole message, PDF and all, only when the preview can't settle it
                if needsFullMessage {
                    let raw = try await session.withOperationTimeout {
                        try await self.session.command(self.fetchCommand(for: uid.raw))
                    }
                    if !IMAPResponse.taggedSuccess(raw) {
                        throw EmailFetchError.fetchFailed
                    }
                    parsed = parseEmail(raw, uid: uid.raw)
                }

                await progress?(
                    EmailFetchProgress(
                        found: matchingUIDs.count,
                        processed: index + 1,
                        skipped: failedUIDs.count + rejectedUIDs.count,
                        latestWarning: nil
                    )
                )

                if !parsed.isEmpty {
                    emails.append(contentsOf: parsed)
                } else {
                    // Read through and not a usable check-in ticket: a settled
                    // verdict, so this one is not queued for a retry.
                    rejectedUIDs.append(uid.numeric)
                    let warning = String(localized: "Skipped email \(uid.raw): no check-in ticket found")
                    latestWarning = warning
                    warnings.append(warning)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedUIDs.append(uid.numeric)
                let warning = String(
                    localized: "Skipped email \(uid.raw): \(error.localizedDescription)"
                )
                latestWarning = warning
                warnings.append(warning)
                session.close()

                if index < matchingUIDs.count - 1 {
                    do {
                        _ = try await session.openMailbox(folder: openedFolder)
                    } catch {
                        let remaining = matchingUIDs[(index + 1)...].map { $0.numeric }
                        failedUIDs.append(contentsOf: remaining)
                        let reconnectWarning = String(
                            localized: "Could not reconnect to continue scanning: \(error.localizedDescription)"
                        )
                        warnings.append(reconnectWarning)
                        await progress?(
                            EmailFetchProgress(
                                found: matchingUIDs.count,
                                processed: matchingUIDs.count,
                                skipped: failedUIDs.count + rejectedUIDs.count,
                                latestWarning: reconnectWarning
                            )
                        )
                        break
                    }
                }
            }
            await progress?(
                EmailFetchProgress(
                    found: matchingUIDs.count,
                    processed: index + 1,
                    skipped: failedUIDs.count + rejectedUIDs.count,
                    latestWarning: latestWarning
                )
            )
        }

        return EmailFetchResult(
            emails: emails.sorted { $0.date > $1.date },
            failedUIDs: Array(Set(failedUIDs)).sorted(),
            rejectedUIDs: Array(Set(rejectedUIDs)).sorted(),
            warnings: warnings,
            highestUID: newUIDs.last?.numeric ?? effectiveLastUID,
            uidValidity: currentUIDValidity,
            didResetUIDValidity: didResetUIDValidity,
            foundCount: matchingUIDs.count
        )
    }

    /// An Italo email's seat, barcode picture and the receipt's total.
    func fetchItaloDetails(forUID uid: String, leg: Int, emailDate: Date) async throws -> ItaloTicketDetails {
        session.useLargeMessageLimits(true)
        defer { session.useLargeMessageLimits(false) }
        _ = try await session.openPassMailbox()
        defer { session.close() }

        let response = try await session.command("UID FETCH \(uid) (BODY.PEEK[])")
        let message = IMAPResponse.messageContent(from: response) ?? response
        let decoded = EmailBodyDecoder.decode(body: message, headers: message)
        let journey = ItaloEmailParser.parseAll(html: decoded.text, emailDate: emailDate).first { $0.leg == leg }
        let images = EmailMIMEExtractor.imageAttachments(from: message)
        let pdfs = decoded.pdfs
        return ItaloTicketDetails(
            passengerName: journey?.passengerName ?? "",
            carriage: journey?.carriage ?? 0,
            seat: journey?.seat ?? "",
            // a round trip's total belongs to the booking, so it sits on the outbound
            price: leg == 0 ? pdfs.lazy.compactMap(ItaloEmailParser.price(inPDF:)).first : nil,
            // barcode-1.png is the outbound's, barcode-2.png the return's
            barcode: images.indices.contains(leg) ? images[leg] : Data()
        )
    }

    func fetchPDFs(forUID uid: String) async throws -> [Data] {
        // the UID came from the scan, so it only means something in the mailbox the
        // scan read — Gmail's All Mail, whose UIDs differ from the inbox's
        session.useLargeMessageLimits(true)
        defer { session.useLargeMessageLimits(false) }
        _ = try await session.openPassMailbox()
        defer { session.close() }

        let response = try await session.command("UID FETCH \(uid) (BODY.PEEK[])")
        let searchable = IMAPResponse.messageContent(from: response) ?? response
        let decoded1 = EmailBodyDecoder.decode(body: searchable, headers: searchable)
        let decoded2 = EmailBodyDecoder.decode(body: response, headers: response)
        return decoded1.pdfs + decoded2.pdfs
    }
}
