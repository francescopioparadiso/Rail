import Foundation
import Network

enum IMAPError: Error {
    case connectionFailed
    case timeout
    case authFailed
    case invalidResponse
}

class IMAPClient {
    private var connection: NWConnection?
    private var buffer = Data()
    private var currentTag = 1
    
    struct EmailResult: Identifiable {
        let id = UUID()
        let date: Date
        let dateString: String
        let urls: [String]
        
        var trainNumber: String?
        var depStation: String?
        var arrStation: String?
        var depDate: String?
    }
    
    func fetchTrenitaliaEmails(provider: String, email: String, appPassword: String) async throws -> [EmailResult] {
        let host = provider.lowercased() == "google" ? "imap.gmail.com" : "imap.mail.me.com"
        
        try await connect(host: host, port: 993)
        defer { connection?.cancel() }
        
        // Wait for greeting
        _ = try await readUntil(sequence: "\r\n")
        
        // Login
        let loginRes = try await sendCommand("LOGIN \"\(email)\" \"\(appPassword)\"")
        guard loginRes.contains("OK") else { throw IMAPError.authFailed }
        
        // Select Inbox
        _ = try await sendCommand("SELECT INBOX")
        
        // Search
        let searchRes = try await sendCommand("SEARCH FROM \"trenitalia\"")
        let uids = parseSearch(response: searchRes)
        
        guard !uids.isEmpty else { return [] }
        
        // Take last 20 UIDs
        let recentUIDs = Array(uids.suffix(20))
        var results: [EmailResult] = []
        
        for uid in recentUIDs.reversed() {
            let fetchRes = try await sendCommand("FETCH \(uid) (BODY.PEEK[])")
            if let result = parseEmail(raw: fetchRes) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private class ContinuationState {
        var isResumed = false
        let lock = NSLock()
        
        func tryResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if !isResumed {
                isResumed = true
                return true
            }
            return false
        }
    }
    
    private func connect(host: String, port: UInt16) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
            let params = NWParameters.tls
            connection = NWConnection(to: endpoint, using: params)
            
            let state = ContinuationState()
            connection?.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    if state.tryResume() {
                        continuation.resume()
                    }
                case .failed(let error):
                    if state.tryResume() {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    if state.tryResume() {
                        continuation.resume(throwing: IMAPError.connectionFailed)
                    }
                default:
                    break
                }
            }
            connection?.start(queue: DispatchQueue.global())
        }
    }
    
    private func sendCommand(_ cmd: String) async throws -> String {
        let tag = "A\(String(format: "%03d", currentTag))"
        currentTag += 1
        
        let fullCmd = "\(tag) \(cmd)\r\n"
        try await write(data: fullCmd.data(using: .utf8)!)
        
        // Read until we see the tag OK, NO, or BAD
        var response = ""
        while true {
            let line = try await readUntil(sequence: "\r\n")
            response += line + "\r\n"
            
            // If the line starts with our tag, it's the completion line
            if line.hasPrefix(tag) {
                break
            }
            
            // Handle IMAP literals (e.g. {1234}\r\n)
            if line.hasSuffix("}") {
                if let range = line.range(of: "{", options: .backwards) {
                    let numStr = line[line.index(after: range.lowerBound)..<line.index(before: line.endIndex)]
                    if let bytesToRead = Int(numStr) {
                        let literalData = try await readExact(length: bytesToRead)
                        if let literalStr = String(data: literalData, encoding: .utf8) ?? String(data: literalData, encoding: .ascii) {
                            response += literalStr
                        } else {
                            response += String(decoding: literalData, as: UTF8.self)
                        }
                    }
                }
            }
        }
        return response
    }
    
    private func write(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func readUntil(sequence: String) async throws -> String {
        let seqData = sequence.data(using: .utf8)!
        
        while true {
            if let range = buffer.range(of: seqData) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .ascii) ?? ""
            }
            
            let chunk = try await readChunk()
            buffer.append(chunk)
        }
    }
    
    private func readExact(length: Int) async throws -> Data {
        while buffer.count < length {
            let chunk = try await readChunk()
            buffer.append(chunk)
        }
        
        let data = buffer.subdata(in: 0..<length)
        buffer.removeSubrange(0..<length)
        return data
    }
    
    private func readChunk() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: IMAPError.connectionFailed)
                }
            }
        }
    }
    
    private func parseSearch(response: String) -> [String] {
        // Look for "* SEARCH 1 2 3"
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            if line.uppercased().hasPrefix("* SEARCH ") {
                let parts = line.components(separatedBy: " ")
                if parts.count > 2 {
                    return Array(parts[2...])
                }
            }
        }
        return []
    }
    
    private func parseEmail(raw: String) -> EmailResult? {
        // Strip IMAP artifacts and quoted-printable soft line breaks
        var cleanRaw = raw.replacingOccurrences(of: "=\r\n", with: "")
        cleanRaw = cleanRaw.replacingOccurrences(of: "=\n", with: "")
        
        // Extract Date
        var date: Date = Date()
        var dateString = "Unknown"
        if let dateRange = raw.range(of: "(?i)^Date: (.*?)\r\n", options: .regularExpression) {
            let dateStrRaw = String(raw[dateRange]).replacingOccurrences(of: "Date: ", with: "").replacingOccurrences(of: "date: ", with: "").replacingOccurrences(of: "\r\n", with: "")
            dateString = dateStrRaw
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            if let d = formatter.date(from: dateStrRaw) {
                date = d
            }
        }
        
        let lower = cleanRaw.lowercased()
        if lower.contains("pnr") || lower.contains("barcode") || lower.contains("biglietto") {
            // Find lefrecce URLs
            let pattern = "https?://[^\\s\"\'<>\n]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = cleanRaw as NSString
                let results = regex.matches(in: cleanRaw, range: NSRange(location: 0, length: nsString.length))
                var urls = results.map { nsString.substring(with: $0.range) }
                
                // Filter for lefrecce.it and self-check-in
                urls = urls.filter { $0.contains("lefrecce.it") }
                urls = urls.map { $0.replacingOccurrences(of: "&amp;", with: "&") }
                
                let checkinUrls = urls.filter { $0.contains("self-check-in") }
                if !checkinUrls.isEmpty {
                    
                    // Simple Regex to extract Train info from text email
                    var trainNumber: String?
                    var depStation: String?
                    var arrStation: String?
                    var depDate: String?
                    
                    // Patterns often found in Trenitalia emails:
                    if let m = try? NSRegularExpression(pattern: "(?i)Treno:?\\s*([A-Za-z0-9]+)").firstMatch(in: cleanRaw, range: NSRange(location: 0, length: nsString.length)) {
                        trainNumber = nsString.substring(with: m.range(at: 1))
                    }
                    if let m = try? NSRegularExpression(pattern: "(?i)Data:?\\s*(\\d{2}/\\d{2}/\\d{4})").firstMatch(in: cleanRaw, range: NSRange(location: 0, length: nsString.length)) {
                        depDate = nsString.substring(with: m.range(at: 1))
                    }
                    if let m = try? NSRegularExpression(pattern: "(?i)Da:\\s*([^\\n]+)").firstMatch(in: cleanRaw, range: NSRange(location: 0, length: nsString.length)) {
                        depStation = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Strip HTML tags if any
                        depStation = depStation?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                    }
                    if let m = try? NSRegularExpression(pattern: "(?i)A:\\s*([^\\n]+)").firstMatch(in: cleanRaw, range: NSRange(location: 0, length: nsString.length)) {
                        arrStation = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        arrStation = arrStation?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                    }
                    
                    return EmailResult(date: date, dateString: dateString, urls: Array(Set(checkinUrls)), trainNumber: trainNumber, depStation: depStation, arrStation: arrStation, depDate: depDate)
                }
            }
        }
        
        return nil
    }
}
