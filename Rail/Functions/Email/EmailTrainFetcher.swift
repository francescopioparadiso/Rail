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

}

struct EmailFetchProgress: Sendable {
    let found: Int
    let processed: Int
    let skipped: Int
    let latestWarning: String?
}

struct EmailFetchResult: Sendable {
    let emails: [FetchedEmail]
    let failedUIDs: [UInt64]
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

    private func fallbackFetchCommand(for uid: String) -> String {
        "UID FETCH \(uid) (BODY.PEEK[TEXT])"
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

    private func parseEmail(_ raw: String, uid: String) -> FetchedEmail? {
        let searchable = IMAPResponse.messageContent(from: raw) ?? raw
        let decoded1 = EmailBodyDecoder.decode(body: searchable, headers: searchable)
        let decoded2 = EmailBodyDecoder.decode(body: raw, headers: raw)
        let decoded = decoded1.text + "\n" + decoded2.text

        print("[EMAIL-DEBUG] UID \(uid): raw=\(raw.count) chars, searchable=\(searchable.count) chars, decoded=\(decoded.count) chars")
        let snippet = String(decoded.prefix(300)).replacingOccurrences(of: "\n", with: "⏎")
        print("[EMAIL-DEBUG] UID \(uid): decoded snippet: \(snippet)")

        // Quick keyword filter like Python: skip if none of these keywords present
        let lower = decoded.lowercased()
        let hasPnr = lower.contains("pnr")
        let hasBarcode = lower.contains("barcode")
        let hasBiglietto = lower.contains("biglietto")
        let hasCheckin = lower.contains("self-check-in")
        guard hasPnr || hasBarcode || hasBiglietto || hasCheckin else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - no keywords (pnr=\(hasPnr), barcode=\(hasBarcode), biglietto=\(hasBiglietto), checkin=\(hasCheckin))")
            return nil
        }
        print("[EMAIL-DEBUG] UID \(uid): keywords found (pnr=\(hasPnr), barcode=\(hasBarcode), biglietto=\(hasBiglietto), checkin=\(hasCheckin))")

        guard let from = IMAPResponse.header("From", in: searchable)
                ?? IMAPResponse.header("From", in: raw)
                ?? IMAPResponse.header("FROM", in: searchable)
                ?? IMAPResponse.header("FROM", in: raw) else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - no From header found")
            return nil
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
        guard isTrenitaliaSender || extractCheckInID(from: decoded) != nil else {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - not trenitalia sender and no check-in ID")
            return nil
        }
        let checkInID = extractCheckInID(from: decoded) ?? ""
        print("[EMAIL-DEBUG] UID \(uid): checkInID=\(checkInID.prefix(40))...")

        // An Abbonamento confirmation carries the same "Il Tuo Biglietto Trenitalia" subject
        // as a ticket, so the search picks it up too. It has no check-in link — that pairing
        // is what separates it from a real ticket, which always has one.
        if checkInID.isEmpty && lower.contains("abbonamento") {
            print("[EMAIL-DEBUG] UID \(uid): SKIPPED - subscription, not a train ticket")
            return nil
        }

        let journey = EmailJourneyParser.parse(from: decoded)
        let date = IMAPResponse.header("Date", in: searchable).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("Date", in: raw).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("DATE", in: searchable).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("DATE", in: raw).flatMap(IMAPResponse.parseDate)
            ?? .distantPast

        print("[EMAIL-DEBUG] UID \(uid): PARSED ✅ train=\(journey?.trainNumber ?? "nil") dep=\(journey?.departureStation ?? "nil") arr=\(journey?.arrivalStation ?? "nil") price=\(journey?.price ?? "nil") date=\(date)")

        return FetchedEmail(
            imapUID: uid,
            checkInID: checkInID,
            date: date,
            departureDate: journey?.departureDate,
            arrivalDate: journey?.arrivalDate,
            trainNumber: journey?.trainNumber ?? "",
            departureStation: journey?.departureStation ?? "",
            arrivalStation: journey?.arrivalStation ?? "",
            price: journey?.price ?? "Unknown"
        )
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

        let newUIDs = IMAPResponse.uids(in: search)
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
        var warnings: [String] = []
        for (index, uid) in matchingUIDs.enumerated() {
            try Task.checkCancellation()
            var latestWarning: String?
            do {
                var raw = try await session.withOperationTimeout {
                    try await self.session.command(self.fetchCommand(for: uid.raw))
                }
                if !IMAPResponse.taggedSuccess(raw) {
                    throw EmailFetchError.fetchFailed
                }

                var parsed = parseEmail(raw, uid: uid.raw)
                if parsed == nil {
                    raw = try await session.withOperationTimeout {
                        try await self.session.command(self.fallbackFetchCommand(for: uid.raw))
                    }
                    if IMAPResponse.taggedSuccess(raw) {
                        parsed = parseEmail(raw, uid: uid.raw)
                    }
                }

                await progress?(
                    EmailFetchProgress(
                        found: matchingUIDs.count,
                        processed: index + 1,
                        skipped: failedUIDs.count,
                        latestWarning: nil
                    )
                )

                if let parsed {
                    emails.append(parsed)
                } else {
                    // Downloaded successfully but not a usable check-in ticket.
                    failedUIDs.append(uid.numeric)
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
                                skipped: failedUIDs.count,
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
                    skipped: failedUIDs.count,
                    latestWarning: latestWarning
                )
            )
        }

        return EmailFetchResult(
            emails: emails.sorted { $0.date > $1.date },
            failedUIDs: Array(Set(failedUIDs)).sorted(),
            warnings: warnings,
            highestUID: newUIDs.last?.numeric ?? effectiveLastUID,
            uidValidity: currentUIDValidity,
            didResetUIDValidity: didResetUIDValidity,
            foundCount: matchingUIDs.count
        )
    }

    func fetchPDFs(forUID uid: String) async throws -> [Data] {
        _ = try await session.openMailbox()
        defer { session.close() }

        let response = try await session.command("UID FETCH \(uid) (BODY.PEEK[])")
        let searchable = IMAPResponse.messageContent(from: response) ?? response
        let decoded1 = EmailBodyDecoder.decode(body: searchable, headers: searchable)
        let decoded2 = EmailBodyDecoder.decode(body: response, headers: response)
        return decoded1.pdfs + decoded2.pdfs
    }
}
