import Foundation

internal enum EmailBodyDecoder {
    nonisolated static func decode(body: String, headers: String) -> (text: String, pdfs: [Data]) {
        if let boundary = boundary(in: headers) {
            let parts = body.components(separatedBy: "--\(boundary)")
            var fullText = ""
            var allPdfs: [Data] = []
            for part in parts {
                let decoded = decodePart(part)
                fullText += decoded.text
                allPdfs.append(contentsOf: decoded.pdfs)
            }
            return (fullText, allPdfs)
        }
        return decodePart(body)
    }

    nonisolated static func unescapeQuotedPrintable(_ text: String) -> String {
        decodeQuotedPrintable(text)
    }

    nonisolated static func boundary(in headers: String) -> String? {
        if let direct = boundaryFromHeaders(headers) { return direct }
        // BODY[TEXT] often embeds the multipart headers inside the literal.
        guard let regex = try? NSRegularExpression(
            pattern: #"boundary="?([^"\s;\r\n]+)"?"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(headers.startIndex..., in: headers)
        guard let match = regex.firstMatch(in: headers, range: range),
              let capture = Range(match.range(at: 1), in: headers) else { return nil }
        return String(headers[capture])
    }

    nonisolated private static func boundaryFromHeaders(_ headers: String) -> String? {
        guard let contentType = header("Content-Type", in: headers) else { return nil }
        guard let range = contentType.range(of: "boundary=", options: .caseInsensitive) else { return nil }

        let value = String(contentType[range.upperBound...])
        if value.hasPrefix("\"") {
            return String(value.dropFirst().prefix(while: { $0 != "\"" }))
        }
        return value.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    nonisolated private static func header(_ name: String, in headers: String) -> String? {
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

    nonisolated private static func decodePart(_ part: String) -> (text: String, pdfs: [Data]) {
        guard let split = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") else {
            return (decodeQuotedPrintable(part), [])
        }

        let partHeaders = String(part[..<split.lowerBound])
        let partBody = String(part[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = header("Content-Type", in: partHeaders)?.lowercased() ?? ""
        if contentType.contains("multipart/"), let nestedBoundary = boundary(in: partHeaders) {
            let parts = partBody.components(separatedBy: "--\(nestedBoundary)")
            var fullText = ""
            var allPdfs: [Data] = []
            for p in parts {
                let decoded = decodePart(p)
                fullText += decoded.text
                allPdfs.append(contentsOf: decoded.pdfs)
            }
            return (fullText, allPdfs)
        }
        
        let encoding = header("Content-Transfer-Encoding", in: partHeaders)?.lowercased() ?? ""
        
        if contentType.contains("application/pdf") {
            if encoding.contains("base64") {
                let collapsed = partBody.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                if let data = Data(base64Encoded: collapsed, options: .ignoreUnknownCharacters) {
                    return ("", [data])
                }
            }
            return ("", [])
        }
        
        if !contentType.isEmpty,
           !contentType.contains("text/plain"),
           !contentType.contains("text/html"),
           !contentType.contains("multipart/") {
            return ("", [])
        }

        if encoding.contains("base64") {
            let collapsed = partBody.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            if let data = Data(base64Encoded: collapsed, options: .ignoreUnknownCharacters), let text = String(data: data, encoding: .utf8) {
                return (text, [])
            }
            if let data = Data(base64Encoded: collapsed, options: .ignoreUnknownCharacters), let text = String(data: data, encoding: .isoLatin1) {
                return (text, [])
            }
        }

        return (decodeQuotedPrintable(partBody), [])
    }

    nonisolated private static func decodeQuotedPrintable(_ text: String) -> String {
        var bytes: [UInt8] = []
        let scalars = Array(text.unicodeScalars)
        var i = 0
        
        while i < scalars.count {
            if scalars[i] == "=" && i + 1 < scalars.count {
                var next = i + 1
                
                // Many clients incorrectly put spaces before the newline in a soft break
                while next < scalars.count && (scalars[next] == " " || scalars[next] == "\t") {
                    next += 1
                }
                
                if next < scalars.count && (scalars[next] == "\r" || scalars[next] == "\n") {
                    i = next
                    if i < scalars.count && scalars[i] == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n" {
                        i += 1 // Skip \n of \r\n
                    }
                    i += 1 // Skip the newline itself
                    continue
                }
                
                next = i + 1
                if next + 1 < scalars.count {
                    let hexStr = String(scalars[next]) + String(scalars[next+1])
                    if let byte = UInt8(hexStr, radix: 16) {
                        bytes.append(byte)
                        i = next + 2
                        continue
                    }
                }
            }
            
            let scalar = scalars[i]
            // text is Latin-1 encoded (from EmailTrainFetcher). Recover the raw byte:
            if scalar.value <= 255 {
                bytes.append(UInt8(scalar.value))
            } else {
                bytes.append(contentsOf: String(scalar).utf8)
            }
            i += 1
        }
        
        if let utf8 = String(bytes: bytes, encoding: .utf8) {
            return utf8
        }
        return String(bytes: bytes, encoding: .isoLatin1) ?? text
    }
}
