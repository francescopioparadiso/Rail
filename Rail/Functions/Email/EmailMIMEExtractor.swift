import Foundation

enum EmailMIMEExtractor {
    nonisolated static func pdfAttachments(from message: String) -> [Data] {
        let normalized = message.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n--")
        var pdfs: [Data] = []
        var seen = Set<Data>()

        for part in parts {
            let lower = part.lowercased()
            let hasPDFName = (lower.contains("name=") || lower.contains("filename="))
                && lower.contains(".pdf")
            let isOctetAttachment = lower.contains("content-type: application/octet-stream")
                && (hasPDFName || (lower.contains("content-disposition:") && lower.contains("attachment")))
            let isPDF = lower.contains("content-type: application/pdf")
                || hasPDFName
                || isOctetAttachment
                || (lower.contains("content-type:") && lower.contains("pdf"))
            guard isPDF else { continue }

            let isBase64 = lower.contains("content-transfer-encoding: base64")
            guard let body = mimeBody(of: part) else { continue }

            if isBase64 {
                if let data = decodeBase64PDF(body) {
                    if seen.insert(data).inserted { pdfs.append(data) }
                }
            } else if body.contains("%PDF"), let data = body.data(using: .isoLatin1) {
                if let pdfRange = data.range(of: Data("%PDF".utf8)) {
                    let pdf = data.subdata(in: pdfRange.lowerBound..<data.endIndex)
                    if seen.insert(pdf).inserted { pdfs.append(pdf) }
                }
            }
        }

        // Fallback: scan for base64 "%PDF" (`JVBERi`) when MIME headers are atypical.
        if pdfs.isEmpty {
            for data in scanBase64PDFBlobs(in: normalized) where seen.insert(data).inserted {
                pdfs.append(data)
            }
        }
        return pdfs
    }

    nonisolated private static func mimeBody(of part: String) -> String? {
        if let range = part.range(of: "\n\n") {
            return String(part[range.upperBound...])
        }
        if let range = part.range(of: "\r\n\r\n") {
            return String(part[range.upperBound...])
        }
        return nil
    }

    nonisolated private static func decodeBase64PDF(_ body: String) -> Data? {
        let collapsed = body
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        // Trim trailing MIME epilogue / boundary noise from the base64 alphabet.
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=").inverted)
        guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              data.starts(with: Data("%PDF".utf8)) else { return nil }
        return data
    }

    nonisolated private static func scanBase64PDFBlobs(in message: String) -> [Data] {
        guard let regex = try? NSRegularExpression(
            pattern: #"JVBERi0[A-Za-z0-9+/=\s]{200,}"#,
            options: []
        ) else { return [] }
        let ns = message as NSString
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: ns.length))
        var pdfs: [Data] = []
        for match in matches.prefix(8) {
            let blob = ns.substring(with: match.range)
            if let data = decodeBase64PDF(blob) {
                pdfs.append(data)
            }
        }
        return pdfs
    }
}
