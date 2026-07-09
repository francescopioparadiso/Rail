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

    // DEBUGGING: fetch details for departures within the last 2 days (instead of future-only)
    var shouldFetchDetails: Bool {
        guard let departureDate else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
        return departureDate > cutoff
    }
}

enum EmailFetchError: Error {
    case connectionFailed
    case authFailed
    case inboxFailed
    case searchFailed
    case fetchFailed
}

final class EmailFetcher {
    private let account: Emails
    private var connection: NWConnection?
    private var buffer = Data()
    private var tag = 1

    init(account: Emails) {
        self.account = account
    }

    private func connect() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            var once = false
            connection = NWConnection(
                to: .hostPort(host: .init(account.provider.server), port: NWEndpoint.Port(rawValue: UInt16(account.provider.port))!),
                using: .tls
            )
            connection?.stateUpdateHandler = { state in
                guard !once else { return }
                switch state {
                case .ready: once = true; done.resume()
                case .failed(let error): once = true; done.resume(throwing: error)
                case .cancelled: once = true; done.resume(throwing: EmailFetchError.connectionFailed)
                default: break
                }
            }
            connection?.start(queue: .global())
        }
    }

    private func close() {
        connection?.cancel()
        connection = nil
        buffer = Data()
        tag = 1
    }

    private func command(_ text: String) async throws -> String {
        let id = "A\(String(format: "%03d", tag))"
        tag += 1
        try await send("\(id) \(text)\r\n".data(using: .utf8)!)

        var out = ""
        while true {
            let row = try await readLine()
            out += row + "\r\n"
            if row.hasPrefix(id) { break }
            if row.hasSuffix("}"), let open = row.lastIndex(of: "{"),
               let n = Int(row[row.index(after: open)..<row.index(before: row.endIndex)]) {
                out += String(decoding: try await read(n), as: UTF8.self)
            }
        }
        return out
    }

    private func readLine() async throws -> String {
        let sep = Data("\r\n".utf8)
        while !buffer.contains(sep) { buffer.append(try await readChunk()) }
        guard let r = buffer.range(of: sep) else { throw EmailFetchError.connectionFailed }
        let line = Data(buffer[..<r.lowerBound])
        buffer.removeSubrange(0..<r.upperBound)
        return String(decoding: line, as: UTF8.self)
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error { done.resume(throwing: error) }
                else { done.resume() }
            })
        }
    }

    private func read(_ n: Int) async throws -> Data {
        while buffer.count < n { buffer.append(try await readChunk()) }
        let data = Data(buffer.prefix(n))
        buffer.removeSubrange(0..<n)
        return data
    }

    private func readChunk() async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, Error>) in
                    self.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, doneReceiving, error in
                        if let error { done.resume(throwing: error) }
                        else if let data, !data.isEmpty { done.resume(returning: data) }
                        else if doneReceiving { done.resume(throwing: EmailFetchError.connectionFailed) }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw EmailFetchError.connectionFailed
            }
            guard let data = try await group.next() else { throw EmailFetchError.connectionFailed }
            group.cancelAll()
            return data
        }
    }

    private func uids(in response: String) -> [String] {
        response.split(whereSeparator: \.isNewline)
            .first { $0.uppercased().hasPrefix("* SEARCH") }?
            .split(separator: " ").dropFirst(2).map(String.init) ?? []
    }

    private func messageContent(from response: String) -> String? {
        if let literal = response.range(of: #"\{\d+\}\r\n"#, options: .regularExpression) {
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
        guard let message = messageContent(from: raw) else { return nil }
        guard let split = message.range(of: "\r\n\r\n") ?? message.range(of: "\n\n") else { return nil }

        let headers = String(message[..<split.lowerBound])
        let body = decodedBody(from: message)
        guard let from = header("From", in: headers) else { return nil }

        let sender = from.firstIndex(of: "<").flatMap { s in
            from.firstIndex(of: ">").map { String(from[from.index(after: s)..<$0]).lowercased() }
        } ?? from.lowercased()

        guard sender.contains("trenitalia.it") else { return nil }
        guard let checkInID = extractCheckInID(from: body) else { return nil }

        let journey = EmailJourneyParser.parse(from: body)
        let date = header("Date", in: headers).flatMap(parseDate) ?? .distantPast
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

    func fetchEmails(knownIMAPUIDs: Set<String> = []) async throws -> [FetchedEmail] {
        try await connect()
        defer { close() }

        _ = try await readLine()

        let login = try await command("LOGIN \"\(account.email)\" \"\(account.appPassword)\"")
        guard login.contains("OK") else { throw EmailFetchError.authFailed }

        let inbox = try await command("SELECT INBOX")
        guard inbox.contains("OK") else { throw EmailFetchError.inboxFailed }

        let search = try await command("UID SEARCH FROM \"trenitalia\"")
        guard search.contains("OK") else { throw EmailFetchError.searchFailed }

        var emails: [FetchedEmail] = []
        for uid in uids(in: search) where !knownIMAPUIDs.contains(uid) {
            let raw = try await command("UID FETCH \(uid) (BODY.PEEK[])")
            guard raw.contains("OK") else { throw EmailFetchError.fetchFailed }
            if let email = parseEmail(raw, uid: uid) {
                emails.append(email)
            }
        }

        return emails.sorted { $0.date > $1.date }
    }
}

private enum EmailBodyDecoder {
    static func decode(body: String, headers: String) -> String {
        if let boundary = boundary(in: headers) {
            return body
                .components(separatedBy: "--\(boundary)")
                .map { decodePart($0) }
                .joined()
        }
        return decodePart(body)
    }

    private static func boundary(in headers: String) -> String? {
        guard let contentType = header("Content-Type", in: headers) else { return nil }
        guard let range = contentType.range(of: "boundary=\"", options: .caseInsensitive)
            ?? contentType.range(of: "boundary=", options: .caseInsensitive) else { return nil }

        let value = String(contentType[range.upperBound...])
        if value.hasPrefix("\"") {
            return String(value.dropFirst().prefix(while: { $0 != "\"" }))
        }
        return value.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func header(_ name: String, in headers: String) -> String? {
        headers.split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("\(name.lowercased()):") }
            .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func decodePart(_ part: String) -> String {
        guard let split = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") else {
            return decodeQuotedPrintable(part)
        }

        let partHeaders = String(part[..<split.lowerBound])
        let partBody = String(part[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func decodeQuotedPrintable(_ text: String) -> String {
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

    static func parse(from body: String) -> ParsedJourney? {
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

    private static func normalize(_ text: String) -> String {
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

    private static func combine(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    private static func firstCaptureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[captureRange])
        }
    }
}
