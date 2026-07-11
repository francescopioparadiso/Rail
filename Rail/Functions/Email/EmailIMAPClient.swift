import Foundation
import Network

struct FetchedEmail: Sendable {
    let imapUID: String
    let checkInID: String
    let date: Date
    let departureDate: Date?
    let trainNumber: String
    let departureStation: String
    let arrivalStation: String

    var shouldFetchDetails: Bool {
        guard let departureDate else { return false }
        return Calendar.current.startOfDay(for: departureDate) >= Calendar.current.startOfDay(for: .now)
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

private final class ContinuationGate<Value>: @unchecked Sendable {
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

actor EmailFetcher {
    private static let operationTimeout: TimeInterval = 5
    private static let maxLiteralSize = 262_144
    private static let textSnippetSize = 65_536
    private let account: Emails
    private var connection: NWConnection?
    private var buffer = Data()
    private var tag = 1

    init(account: Emails) {
        self.account = account
    }

    private func connect() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(done)
            let connection = NWConnection(
                to: .hostPort(host: .init(account.provider.server), port: NWEndpoint.Port(rawValue: UInt16(account.provider.port))!),
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
        let deadline = Date().addingTimeInterval(Self.operationTimeout)
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
                if size > Self.maxLiteralSize { throw EmailFetchError.fetchFailed }
                let literal = try await read(size, deadline: deadline)
                out += String(decoding: literal, as: UTF8.self)
                guard let literalRange = Self.firstLiteralRange(in: remainder) else { break }
                remainder = String(remainder[literalRange.upperBound...])
            }
        }
        return out
    }

    private func readLine(deadline: Date? = nil) async throws -> String {
        let effectiveDeadline = deadline ?? Date().addingTimeInterval(Self.operationTimeout)
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

    private func withOperationTimeout<T>(
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
        "UID FETCH \(uid) (BODY.PEEK[HEADER.FIELDS (FROM DATE)] BODY.PEEK[TEXT]<0.\(Self.textSnippetSize)>)"
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
        if let literal = response.range(of: #"\{\d+\+?\}\r\n"#, options: .regularExpression) {
            var content = String(response[literal.upperBound...])
            if let end = content.range(of: "\r\n)", options: .backwards) {
                content = String(content[..<end.lowerBound])
            }
            return content
        }

        guard let start = response.range(of: "From:") ?? response.range(of: "Return-Path:") else { return nil }
        return String(response[start.lowerBound...])
    }

    private func decodedBody(from message: String) -> String {
        guard let split = message.range(of: "\r\n\r\n") ?? message.range(of: "\n\n") else { return message }
        let headers = String(message[..<split.lowerBound])
        let rawBody = String(message[split.upperBound...])
        return EmailBodyDecoder.decode(body: rawBody, headers: headers)
    }

    private func extractCheckInID(from body: String) -> String? {
        let clean = body
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")

        let patterns = [
            #"self-check-in[^\"'<>]*[?&]id=([A-Za-z0-9+/_=-]+)"#,
            #"self-check-in\?id=([A-Za-z0-9+/_=-]+)"#
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
        guard let from = header("From", in: searchable) else { return nil }

        let sender = from.firstIndex(of: "<").flatMap { s in
            from.firstIndex(of: ">").map { String(from[from.index(after: s)..<$0]).lowercased() }
        } ?? from.lowercased()

        guard sender.contains("trenitalia.it") else { return nil }
        guard let checkInID = extractCheckInID(from: searchable) else { return nil }

        let journey = EmailJourneyParser.parse(from: searchable)
        let date = header("Date", in: searchable).flatMap(parseDate) ?? .distantPast
        return FetchedEmail(
            imapUID: uid,
            checkInID: checkInID,
            date: date,
            departureDate: journey?.departureDate,
            trainNumber: journey?.trainNumber ?? "",
            departureStation: journey?.departureStation ?? "",
            arrivalStation: journey?.arrivalStation ?? ""
        )
    }

    private func header(_ name: String, in headers: String) -> String? {
        headers.split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("\(name.lowercased()):") }
            .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func parseDate(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.date(from: value)
    }

    private func openMailbox() async throws -> String {
        do {
            try await connect()
            _ = try await readLine()

            let login = try await command("LOGIN \"\(account.email)\" \"\(account.appPassword)\"")
            guard login.contains("OK") else { throw EmailFetchError.authFailed }

            let inbox = try await command("SELECT INBOX")
            guard inbox.contains("OK") else { throw EmailFetchError.inboxFailed }
            return inbox
        } catch {
            close()
            throw error
        }
    }

    func fetchEmails(
        afterUID: UInt64?,
        expectedUIDValidity: UInt64?,
        retryUIDs: [UInt64],
        progress: (@MainActor @Sendable (EmailFetchProgress) -> Void)? = nil
    ) async throws -> EmailFetchResult {
        try Task.checkCancellation()
        let inbox = try await openMailbox()
        defer { close() }

        let currentUIDValidity = uidValidity(in: inbox)
        let didResetUIDValidity = expectedUIDValidity != nil
            && currentUIDValidity != nil
            && expectedUIDValidity != currentUIDValidity
        let effectiveLastUID = didResetUIDValidity ? nil : afterUID
        let searchCommand: String
        if let effectiveLastUID, effectiveLastUID < UInt64.max {
            searchCommand = "UID SEARCH UID \(effectiveLastUID + 1):* FROM \"trenitalia\""
        } else if effectiveLastUID == UInt64.max {
            searchCommand = "UID SEARCH UID \(UInt64.max):\(UInt64.max) FROM \"trenitalia\""
        } else {
            searchCommand = "UID SEARCH FROM \"trenitalia\""
        }

        let search = try await command(searchCommand)
        guard search.contains("OK") else { throw EmailFetchError.searchFailed }

        let newUIDs = uids(in: search)
            .compactMap { uid in UInt64(uid).map { (raw: uid, numeric: $0) } }
            .filter { item in
                guard let effectiveLastUID else { return true }
                return item.numeric > effectiveLastUID
            }
            .sorted { $0.numeric < $1.numeric }
        let retryValues = didResetUIDValidity ? [] : retryUIDs
        var uidsByValue = Dictionary(uniqueKeysWithValues: newUIDs.map { ($0.numeric, $0) })
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
                let raw = try await withOperationTimeout {
                    try await self.command(self.fetchCommand(for: uid.raw))
                }
                guard raw.contains("OK") else { throw EmailFetchError.fetchFailed }

                await progress?(
                    EmailFetchProgress(
                        found: matchingUIDs.count,
                        processed: index + 1,
                        skipped: failedUIDs.count,
                        latestWarning: nil
                    )
                )

                if let email = parseEmail(raw, uid: uid.raw) {
                    emails.append(email)
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
                        _ = try await openMailbox()
                    } catch {
                        let remaining = matchingUIDs[(index + 1)...].map(\.numeric)
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
}

private enum EmailBodyDecoder {
    nonisolated static func decode(body: String, headers: String) -> String {
        if let boundary = boundary(in: headers) {
            return body
                .components(separatedBy: "--\(boundary)")
                .map { decodePart($0) }
                .joined()
        }
        return decodePart(body)
    }

    nonisolated private static func boundary(in headers: String) -> String? {
        guard let contentType = header("Content-Type", in: headers) else { return nil }
        guard let range = contentType.range(of: "boundary=\"", options: .caseInsensitive)
            ?? contentType.range(of: "boundary=", options: .caseInsensitive) else { return nil }

        let value = String(contentType[range.upperBound...])
        if value.hasPrefix("\"") {
            return String(value.dropFirst().prefix(while: { $0 != "\"" }))
        }
        return value.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    nonisolated private static func header(_ name: String, in headers: String) -> String? {
        headers.split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("\(name.lowercased()):") }
            .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    nonisolated private static func decodePart(_ part: String) -> String {
        guard let split = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") else {
            return decodeQuotedPrintable(part)
        }

        let partHeaders = String(part[..<split.lowerBound])
        let partBody = String(part[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = header("Content-Type", in: partHeaders)?.lowercased() ?? ""
        if contentType.contains("multipart/"), let nestedBoundary = boundary(in: partHeaders) {
            return partBody
                .components(separatedBy: "--\(nestedBoundary)")
                .map { decodePart($0) }
                .joined()
        }
        if !contentType.isEmpty,
           !contentType.contains("text/plain"),
           !contentType.contains("text/html"),
           !contentType.contains("multipart/") {
            return ""
        }
        let encoding = header("Content-Transfer-Encoding", in: partHeaders)?.lowercased() ?? ""

        if encoding.contains("base64") {
            let collapsed = partBody.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            if let data = Data(base64Encoded: collapsed), let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let data = Data(base64Encoded: collapsed), let text = String(data: data, encoding: .isoLatin1) {
                return text
            }
        }

        return decodeQuotedPrintable(partBody)
    }

    nonisolated private static func decodeQuotedPrintable(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "=", text.index(after: index) < text.endIndex {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\r" || text[next] == "\n" {
                    index = text.index(after: next)
                    if index < text.endIndex, text[index] == "\n" { index = text.index(after: index) }
                    continue
                }

                if text.distance(from: next, to: text.endIndex) >= 2 {
                    let hexStart = next
                    let hexEnd = text.index(hexStart, offsetBy: 2)
                    let hex = String(text[hexStart..<hexEnd])
                    if let byte = UInt8(hex, radix: 16) {
                        result.append(Character(UnicodeScalar(byte)))
                        index = hexEnd
                        continue
                    }
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }
}

enum EmailJourneyParser {
    struct ParsedJourney {
        let departureDate: Date
        let trainNumber: String
        let departureStation: String
        let arrivalStation: String
    }

    nonisolated static func parse(from body: String) -> ParsedJourney? {
        let text = normalize(body)
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")

        let trainNumber: String
        let journeyDate: String

        if let trainMatch = firstCaptureGroups(
            in: collapsed,
            pattern: #"(?i)(?:Frecciarossa|Frecciargento|Freccialink|Intercity|Regionale|Treno)?\s*(\d{3,5})\s+del\s+(\d{2}/\d{2}/\d{4})"#
        ), trainMatch.count >= 2 {
            trainNumber = trainMatch[0]
            journeyDate = trainMatch[1]
        } else if let reversedMatch = firstCaptureGroups(
            in: collapsed,
            pattern: #"(?i)del\s+(\d{2}/\d{2}/\d{4}).*?(?:Frecciarossa|Frecciargento|Freccialink|Intercity|Regionale|Treno)?\s*(\d{3,5})"#
        ), reversedMatch.count >= 2 {
            journeyDate = reversedMatch[0]
            trainNumber = reversedMatch[1]
        } else {
            return nil
        }

        guard let routeMatch = firstCaptureGroups(
            in: collapsed,
            pattern: #"([^(]+?)\(\s*(\d{1,2}:\d{2})\s*\)\s*-\s*([^(]+?)\(\s*(\d{1,2}:\d{2})\s*\)"#
        ), routeMatch.count >= 4 else { return nil }

        let departureStation = routeMatch[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let departureTime = routeMatch[1]
        let arrivalStation = routeMatch[2].trimmingCharacters(in: .whitespacesAndNewlines)

        guard let departureDate = combine(date: journeyDate, time: departureTime) else { return nil }

        return ParsedJourney(
            departureDate: departureDate,
            trainNumber: trainNumber,
            departureStation: departureStation,
            arrivalStation: arrivalStation
        )
    }

    nonisolated private static func normalize(_ text: String) -> String {
        var result = text
        for separator in ["\u{00A0}", "\u{2009}", "\u{202F}", "&nbsp;"] {
            result = result.replacingOccurrences(of: separator, with: " ")
        }
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>"] {
            result = result.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    nonisolated private static func combine(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    nonisolated private static func firstCaptureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[captureRange])
        }
    }
}
