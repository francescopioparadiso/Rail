import Foundation
import Network

/// Wraps a `CheckedContinuation` so the first caller to finish wins and later
/// resumes are dropped, which `NWConnection` callbacks would otherwise trip on.
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

/// A single TLS IMAP connection: dial, issue tagged commands, read literals and
/// select a mailbox. `EmailTrainFetcher` and `EmailPassFetcher` each own one of
/// these and inherit its isolation, so the connection needs no lock of its own;
/// everything above the transport lives in those two types.
nonisolated final class IMAPSession {

    // MARK: - Limits

    private static let operationTimeout: TimeInterval = 45
    /// Full pass emails with base64 PDFs need a longer per-command deadline than ticket HTML snippets.
    private static let passOperationTimeout: TimeInterval = 120
    /// Tickets carry no PDF attachments but can include a few inline images; give plenty of
    /// headroom now that the fetch is unbounded (no more `<0.N>` partial range).
    private static let maxLiteralSize = 10_485_760
    /// Pass PDFs are larger base64 MIME parts; allow up to ~5 MB per literal.
    private static let passMaxLiteralSize = 5_242_880

    // MARK: - State

    private let account: Emails
    private var connection: NWConnection?
    private var buffer = Data()
    private var tag = 1
    private var activeMaxLiteralSize = IMAPSession.maxLiteralSize
    private var activeCommandTimeout = IMAPSession.operationTimeout

    init(account: Emails) {
        self.account = account
    }

    /// Raises the per-command deadline and literal ceiling for mailboxes carrying
    /// PDF attachments. Passing `false` restores the ticket-sized defaults.
    func useLargeMessageLimits(_ enabled: Bool) {
        activeMaxLiteralSize = enabled ? Self.passMaxLiteralSize : Self.maxLiteralSize
        activeCommandTimeout = enabled ? Self.passOperationTimeout : Self.operationTimeout
    }

    // MARK: - Connection

    func connect() async throws {
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

    func close() {
        connection?.cancel()
        connection = nil
        buffer = Data()
        tag = 1
    }

    func command(_ text: String) async throws -> String {
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

    func readLine(deadline: Date? = nil) async throws -> String {
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

    func send(_ data: Data, deadline: Date) async throws {
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

    func read(_ n: Int, deadline: Date) async throws -> Data {
        while buffer.count < n {
            if Date() > deadline { throw EmailFetchError.timedOut }
            buffer.append(try await readChunk(deadline: deadline))
        }
        let data = Data(buffer.prefix(n))
        buffer.removeSubrange(0..<n)
        return data
    }

    func readChunk(deadline: Date) async throws -> Data {
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

    func withOperationTimeout<T: Sendable>(
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

    // MARK: - Mailbox selection

    func openMailbox() async throws -> String {
        try await openMailbox(folder: "INBOX")
    }

    func openMailbox(folder: String) async throws -> String {
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

    /// Connect, login, then select the pass mailbox (Gmail All Mail when available).
    func openPassMailbox() async throws -> (response: String, folder: String) {
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

    /// Gmail archives Trenitalia receipts; prefer All Mail (localized name via \\All).
    func resolvePassMailboxFolder() async throws -> String {
        let usesGmail = account.provider == .google
            || account.imapServer.lowercased().contains("gmail")
        guard usesGmail else { return "INBOX" }

        let listed = try await command("LIST \"\" \"*\"")
        if let name = Self.allMailFolderName(in: listed) {
            return name
        }
        // Localized fallbacks when LIST parsing misses \\All
        if listed.contains("[Gmail]/Tutti i messaggi") {
            return "[Gmail]/Tutti i messaggi"
        }
        if listed.contains("[Gmail]/All Mail") {
            return "[Gmail]/All Mail"
        }
        return "INBOX"
    }

    // MARK: - Helpers

    static func quotedMailbox(_ folder: String) -> String {
        if folder == "INBOX" { return folder }
        if folder.contains("\"") { return folder }
        return "\"\(folder)\""
    }

    static func allMailFolderName(in listResponse: String) -> String? {
        for line in listResponse.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.uppercased().contains("\\ALL") else { continue }
            guard let regex = try? NSRegularExpression(pattern: #""([^"]+)""#),
                  let match = regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).last,
                  let range = Range(match.range(at: 1), in: line) else { continue }
            return String(line[range])
        }
        return nil
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
}

/// Pure parsers over raw IMAP response text. Free functions on an enum so both
/// fetchers can call them without hopping onto the session actor.
nonisolated enum IMAPResponse {

    static func taggedSuccess(_ response: String) -> Bool {
        response.range(of: #"(?m)^A\d+ OK\b"#, options: .regularExpression) != nil
    }

    static func uids(in response: String) -> [String] {
        response.split(whereSeparator: \.isNewline)
            .first { $0.uppercased().hasPrefix("* SEARCH") }?
            .split(separator: " ").dropFirst(2).map(String.init) ?? []
    }

    static func uidValidity(in response: String) -> UInt64? {
        guard let match = response.range(
            of: #"UIDVALIDITY\s+(\d+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let value = response[match]
            .split(whereSeparator: { !$0.isNumber })
            .last
        return value.flatMap { UInt64($0) }
    }

    static func messageContent(from response: String) -> String? {
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

    static func header(_ name: String, in headers: String) -> String? {
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

    static func parseDate(_ value: String) -> Date? {
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
}
