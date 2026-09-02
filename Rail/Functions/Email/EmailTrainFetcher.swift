import Foundation
import Network

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

    var shouldFetchDetails: Bool {
        guard let departureDate else { return false }
        return EmailContent.isUpcomingDeparture(departureDate)
    }
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

internal final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Error>?

    nonisolated init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    nonisolated func resume(with result: Result<Value, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

actor EmailTrainFetcher {
    private static let operationTimeout: TimeInterval = 45
    /// Full pass emails with base64 PDFs need a longer per-command deadline than ticket HTML snippets.
    private static let passOperationTimeout: TimeInterval = 120
    /// Tickets carry no PDF attachments but can include a few inline images; give plenty of
    /// headroom now that the fetch is unbounded (no more `<0.N>` partial range).
    private static let maxLiteralSize = 10_485_760
    /// Pass PDFs are larger base64 MIME parts; allow up to ~5 MB per literal.
    private static let passMaxLiteralSize = 5_242_880
    private let account: Emails
    private var connection: NWConnection?
    private var buffer = Data()
    private var tag = 1
    private var activeMaxLiteralSize = EmailTrainFetcher.maxLiteralSize
    private var activeCommandTimeout = EmailTrainFetcher.operationTimeout

    init(account: Emails) {
        self.account = account
    }

    private func connect() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(done)
            let connection = NWConnection(
                to: .hostPort(host: .init(account.imapServer), port: NWEndpoint.Port(rawValue: UInt16(account.imapPort))!),
                using: .tls
            )
            self.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume(with: .success(()))
                case .failed(let error):
                    gate.resume(with: .failure(error))
                case .cancelled:
                    gate.resume(with: .failure(EmailFetchError.connectionFailed))
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.operationTimeout) {
                gate.resume(with: .failure(EmailFetchError.timedOut))
            }
        }
    }

    private func close() {
        connection?.cancel()
        connection = nil
        buffer = Data()
        tag = 1
    }

    private func command(_ text: String) async throws -> String {
        let deadline = Date().addingTimeInterval(activeCommandTimeout)
        let id = "A\(String(format: "%03d", tag))"
        tag += 1
        try await send("\(id) \(text)\r\n".data(using: .utf8)!, deadline: deadline)

        var out = ""
        while true {
            try Task.checkCancellation()
            if Date() > deadline { throw EmailFetchError.timedOut }
            let row = try await readLine(deadline: deadline)
            out += row + "\r\n"
            if row.hasPrefix(id) { break }
            var remainder = row
            while let size = Self.firstLiteralSize(in: remainder) {
                if size > activeMaxLiteralSize { throw EmailFetchError.fetchFailed }
                let literal = try await read(size, deadline: deadline)
                // Prefer Latin-1 so base64 PDF bodies stay byte-stable as characters.
                out += String(bytes: literal, encoding: .isoLatin1) ?? String(decoding: literal, as: UTF8.self)
                guard let literalRange = Self.firstLiteralRange(in: remainder) else { break }
                remainder = String(remainder[literalRange.upperBound...])
            }
        }
        return out
    }

    private func readLine(deadline: Date? = nil) async throws -> String {
        let effectiveDeadline = deadline ?? Date().addingTimeInterval(activeCommandTimeout)
        if Date() > effectiveDeadline { throw EmailFetchError.timedOut }
        let sep = Data("\r\n".utf8)
        while !buffer.contains(sep) {
            if Date() > effectiveDeadline { throw EmailFetchError.timedOut }
            buffer.append(try await readChunk(deadline: effectiveDeadline))
        }
        guard let r = buffer.range(of: sep) else { throw EmailFetchError.connectionFailed }
        let line = Data(buffer[..<r.lowerBound])
        buffer.removeSubrange(0..<r.upperBound)
        return String(decoding: line, as: UTF8.self)
    }

    private func send(_ data: Data, deadline: Date) async throws {
        guard let connection else { throw EmailFetchError.connectionFailed }
        let delay = deadline.timeIntervalSinceNow
        guard delay > 0 else { throw EmailFetchError.timedOut }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(done)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { gate.resume(with: .failure(error)) }
                else { gate.resume(with: .success(())) }
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                gate.resume(with: .failure(EmailFetchError.timedOut))
            }
        }
    }

    private func read(_ n: Int, deadline: Date) async throws -> Data {
        while buffer.count < n {
            if Date() > deadline { throw EmailFetchError.timedOut }
            buffer.append(try await readChunk(deadline: deadline))
        }
        let data = Data(buffer.prefix(n))
        buffer.removeSubrange(0..<n)
        return data
    }

    private func readChunk(deadline: Date) async throws -> Data {
        guard let connection else { throw EmailFetchError.connectionFailed }
        let delay = deadline.timeIntervalSinceNow
        guard delay > 0 else { throw EmailFetchError.timedOut }
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, Error>) in
            let gate = ContinuationGate(done)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, doneReceiving, error in
                if let error {
                    gate.resume(with: .failure(error))
                } else if let data, !data.isEmpty {
                    gate.resume(with: .success(data))
                } else if doneReceiving {
                    gate.resume(with: .failure(EmailFetchError.connectionFailed))
                } else {
                    gate.resume(with: .failure(EmailFetchError.connectionFailed))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                gate.resume(with: .failure(EmailFetchError.timedOut))
            }
        }
    }

    static func firstLiteralSize(in line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\{(\d+)\+?\}"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[range])
    }

    static func firstLiteralRange(in line: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: #"\{(\d+)\+?\}"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return range
    }

    private func withOperationTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.operationTimeout))
                throw EmailFetchError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw EmailFetchError.timedOut }
            return result
        }
    }

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

    private func imapTaggedSuccess(_ response: String) -> Bool {
        response.range(of: #"(?m)^A\d+ OK\b"#, options: .regularExpression) != nil
    }

    private func uids(in response: String) -> [String] {
        response.split(whereSeparator: \.isNewline)
            .first { $0.uppercased().hasPrefix("* SEARCH") }?
            .split(separator: " ").dropFirst(2).map(String.init) ?? []
    }

    private func uidValidity(in response: String) -> UInt64? {
        guard let match = response.range(
            of: #"UIDVALIDITY\s+(\d+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let value = response[match]
            .split(whereSeparator: { !$0.isNumber })
            .last
        return value.flatMap { UInt64($0) }
    }

    private func messageContent(from response: String) -> String? {
        // FETCH can return multiple literals (e.g. HEADER + TEXT). Join them all.
        let pattern = #"\{(\d+)\+?\}\r\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            guard let start = response.range(of: "From:") ?? response.range(of: "Return-Path:") else { return nil }
            return String(response[start.lowerBound...])
        }

        let nsRange = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: nsRange)
        guard !matches.isEmpty else {
            guard let start = response.range(of: "From:") ?? response.range(of: "Return-Path:") else { return nil }
            return String(response[start.lowerBound...])
        }

        // `size` below is a BYTE count declared by the IMAP server (e.g. "{4523}"). The
        // literal content was decoded from raw bytes with ISO-Latin-1 (one Unicode scalar
        // per byte, always exactly one UTF-16 code unit), so the UTF-16 view of `response`
        // stays byte-accurate. We must NOT offset using the default Character (extended
        // grapheme cluster) view: Swift collapses "\r\n" into a single Character, and
        // RFC822 messages are full of "\r\n" — so a Character-based offset silently drifts
        // past the real end of the literal (picking up whatever follows it in `response`),
        // or, once it runs out of Characters first, returns nil and drops that chunk of the
        // message outright. Slicing on the UTF-16 view sidesteps both failure modes.
        let utf16 = response.utf16
        var chunks: [String] = []
        for match in matches {
            guard let sizeRange = Range(match.range(at: 1), in: response),
                  let size = Int(response[sizeRange]),
                  let literalHeader = Range(match.range, in: response),
                  let startUTF16 = literalHeader.upperBound.samePosition(in: utf16),
                  let endUTF16 = utf16.index(startUTF16, offsetBy: size, limitedBy: utf16.endIndex) else { continue }
            chunks.append(String(decoding: utf16[startUTF16..<endUTF16], as: UTF16.self))
        }

        let joined = chunks.joined(separator: "\r\n\r\n")
        return joined.isEmpty ? nil : joined
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
        let searchable = messageContent(from: raw) ?? raw
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

        guard let from = header("From", in: searchable)
                ?? header("From", in: raw)
                ?? header("FROM", in: searchable)
                ?? header("FROM", in: raw) else {
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
        let date = header("Date", in: searchable).flatMap(parseDate)
            ?? header("Date", in: raw).flatMap(parseDate)
            ?? header("DATE", in: searchable).flatMap(parseDate)
            ?? header("DATE", in: raw).flatMap(parseDate)
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

    private func header(_ name: String, in headers: String) -> String? {
        let lines = headers.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var values: [String] = []
        var capturing = false
        let prefix = "\(name.lowercased()):"

        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix(prefix) {
                capturing = true
                values = [String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)]
                continue
            }
            if capturing {
                if line.first?.isWhitespace == true || line.hasPrefix("\t") {
                    values.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    break
                }
            }
        }

        let joined = values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private func parseDate(_ value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss ZZZ",
            "dd MMM yyyy HH:mm:ss Z"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private func openMailbox() async throws -> String {
        try await openMailbox(folder: "INBOX")
    }

    private func openMailbox(folder: String) async throws -> String {
        do {
            try await connect()
            _ = try await readLine()

            let login = try await command("LOGIN \"\(account.email)\" \"\(account.appPassword)\"")
            guard login.contains("OK") else { throw EmailFetchError.authFailed }

            let quoted = Self.quotedMailbox(folder)
            let selected = try await command("SELECT \(quoted)")
            guard selected.contains("OK") else { throw EmailFetchError.inboxFailed }
            return selected
        } catch {
            close()
            throw error
        }
    }

    private func openPassMailbox() async throws -> (response: String, folder: String) {
        do {
            try await connect()
            _ = try await readLine()

            let login = try await command("LOGIN \"\(account.email)\" \"\(account.appPassword)\"")
            guard login.contains("OK") else { throw EmailFetchError.authFailed }

            let folder = try await resolvePassMailboxFolder()
            let selected = try await command("SELECT \(Self.quotedMailbox(folder))")
            guard selected.contains("OK") else { throw EmailFetchError.inboxFailed }
            return (selected, folder)
        } catch {
            close()
            throw error
        }
    }

    private static func quotedMailbox(_ folder: String) -> String {
        if folder == "INBOX" { return folder }
        if folder.contains("\"") { return folder }
        return "\"\(folder)\""
    }

    private func resolvePassMailboxFolder() async throws -> String {
        let usesGmail = account.provider == .google
            || account.imapServer.lowercased().contains("gmail")
        guard usesGmail else { return "INBOX" }

        let listed = try await command("LIST \"\" \"*\"")
        if let name = Self.allMailFolderName(in: listed) {
            return name
        }
        if listed.contains("[Gmail]/Tutti i messaggi") {
            return "[Gmail]/Tutti i messaggi"
        }
        if listed.contains("[Gmail]/All Mail") {
            return "[Gmail]/All Mail"
        }
        return "INBOX"
    }

    private static func allMailFolderName(in listResponse: String) -> String? {
        for line in listResponse.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.uppercased().contains("\\ALL") else { continue }
            guard let regex = try? NSRegularExpression(pattern: #""([^"]+)""#),
                  let match = regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).last,
                  let range = Range(match.range(at: 1), in: line) else { continue }
            return String(line[range])
        }
        return nil
    }/// Connects and opens INBOX to confirm email + app password work for fetching.
    func verifyCredentials() async throws {
        try Task.checkCancellation()
        _ = try await openMailbox()
        close()
    }

    func fetchEmails(
        afterUID: UInt64?,
        expectedUIDValidity: UInt64?,
        retryUIDs: [UInt64],
        progress: (@MainActor @Sendable (EmailFetchProgress) -> Void)? = nil
    ) async throws -> EmailFetchResult {
        try Task.checkCancellation()
        let (inbox, openedFolder) = try await openPassMailbox()
        defer { close() }

        let currentUIDValidity = uidValidity(in: inbox)
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
                let response = try await command(commandText)
                if imapTaggedSuccess(response) {
                    search = response
                    break
                }
            } catch {
                continue
            }
        }
        guard !search.isEmpty else { throw EmailFetchError.searchFailed }

        let newUIDs = uids(in: search)
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
                var raw = try await withOperationTimeout {
                    try await self.command(self.fetchCommand(for: uid.raw))
                }
                if !imapTaggedSuccess(raw) {
                    throw EmailFetchError.fetchFailed
                }

                var parsed = parseEmail(raw, uid: uid.raw)
                if parsed == nil {
                    raw = try await withOperationTimeout {
                        try await self.command(self.fallbackFetchCommand(for: uid.raw))
                    }
                    if imapTaggedSuccess(raw) {
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
                close()

                if index < matchingUIDs.count - 1 {
                    do {
                        _ = try await openMailbox(folder: openedFolder)
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
        try await connect()
        _ = try await readLine()
        let login = try await command("LOGIN \"\(account.email)\" \"\(account.appPassword)\"")
        guard login.contains("OK") else { throw EmailFetchError.authFailed }
        let selected = try await command("SELECT \"INBOX\"")
        guard selected.contains("OK") else { throw EmailFetchError.inboxFailed }

        let response = try await command("UID FETCH \(uid) (BODY.PEEK[])")
        let searchable = messageContent(from: response) ?? response
        let decoded1 = EmailBodyDecoder.decode(body: searchable, headers: searchable)
        let decoded2 = EmailBodyDecoder.decode(body: response, headers: response)
        
        defer { close() }
        return decoded1.pdfs + decoded2.pdfs
    }
}
