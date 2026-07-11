import Foundation
import Network

func fetchEmails(email: String, appPassword: String, count: Int) async -> [String] {
    let host = email.lowercased().contains("@gmail.") ? "imap.gmail.com" : "imap.mail.me.com"
    var connection: NWConnection!
    var buffer = Data()
    var tag = 1

    func readChunk() async -> Data {
        await withCheckedContinuation { (done: CheckedContinuation<Data, Never>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                done.resume(returning: data ?? Data())
            }
        }
    }

    func readLine() async -> String {
        let sep = Data("\r\n".utf8)
        while !buffer.contains(sep) {
            let chunk = await readChunk()
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        guard buffer.contains(sep) else { return "" }
        let range = buffer.range(of: sep)!
        let line = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
        buffer.removeSubrange(0..<range.upperBound)
        return line
    }

    func read(_ n: Int) async -> String {
        while buffer.count < n {
            let chunk = await readChunk()
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        let size = min(n, buffer.count)
        let data = Data(buffer.prefix(size))
        buffer.removeSubrange(0..<size)
        return String(decoding: data, as: UTF8.self)
    }

    func command(_ text: String) async -> String {
        let id = "A\(String(format: "%03d", tag))"
        tag += 1
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            connection.send(content: Data("\(id) \(text)\r\n".utf8), completion: .contentProcessed { _ in done.resume() })
        }

        var response = ""
        while true {
            let line = await readLine()
            response += line + "\n"
            if line.hasSuffix("}"), let open = line.lastIndex(of: "{"),
               let size = Int(line[line.index(after: open)..<line.index(before: line.endIndex)]) {
                response += await read(size)
            }
            if line.hasPrefix(id) { break }
        }
        return response
    }

    // connect
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        final class Once: @unchecked Sendable { var value = false }
        let once = Once()
        connection = NWConnection(host: NWEndpoint.Host(host), port: 993, using: .tls)
        connection.stateUpdateHandler = { state in
            if !once.value, case .ready = state {
                once.value = true
                done.resume()
            }
        }
        connection.start(queue: .global())
    }

    // read
    _ = await readLine()
    _ = await command("LOGIN \"\(email)\" \"\(appPassword)\"")
    _ = await command("SELECT INBOX")
    let searchResponse = await command("UID SEARCH FROM \"trenitalia\"")

    // filter
    let uids = searchResponse
        .split(whereSeparator: \.isNewline)
        .first(where: { $0.uppercased().hasPrefix("* SEARCH") })?
        .split(separator: " ")
        .dropFirst(2)
        .map(String.init) ?? []
    let selectedUIDs = uids
        .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
        .prefix(Swift.max(1, count))

    var mails: [String] = []
    for uid in selectedUIDs {
        mails.append(await command("UID FETCH \(uid) (BODY.PEEK[])"))
    }
    connection.cancel()

    return mails
}

// print
Task {
    for mail in await fetchEmails(
        email: "francescopara2003@icloud.com",
        appPassword: "pqmy-ncsd-qzbi-zxte",
        count: 5
    ) {
        print(mail)
        print("-----")
    }
    CFRunLoopStop(CFRunLoopGetMain())
}
RunLoop.main.run()
