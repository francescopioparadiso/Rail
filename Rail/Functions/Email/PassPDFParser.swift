import Foundation
import PDFKit
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct ParsedPassPDF: Sendable {
    let name: String
    let startDate: Date
    let endDate: Date
    let qrImageData: Data
    let price: String
}

/// Pure parsing, safe to run off the main actor during mailbox sync.
nonisolated enum PassPDFParser {
    // MARK: - Properties

    private static let datePatterns: [NSRegularExpression] = {
        let patterns: [(String, NSRegularExpression.Options)] = [
            // Classic single-line: Validità: dal 01/05/2017 al 31/05/2017
            (
                #"validit[àa]\s*:\s*dal\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})\s+al\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})"#,
                [.caseInsensitive]
            ),
            // PDFKit reading order on newer tickets inserts "Validità:" between dates:
            // "dal 01/07/2026 Validità: al 31/07/2026"
            (
                #"dal\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})\s+validit[àa]\s*:?\s*al\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})"#,
                [.caseInsensitive]
            ),
            // Generic dal … al with optional junk between (line breaks / labels)
            (
                #"dal\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4}).{0,48}?al\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})"#,
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                #"valid[oa]\s+(?:dal\s+)?(\d{1,2}[./]\d{1,2}[./]\d{2,4})\s+(?:al|a)\s+(\d{1,2}[./]\d{1,2}[./]\d{2,4})"#,
                [.caseInsensitive]
            ),
            (
                #"(\d{1,2}[./]\d{1,2}[./]\d{2,4})\s*[-–—]\s*(\d{1,2}[./]\d{1,2}[./]\d{2,4})"#,
                [.caseInsensitive]
            )
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0.0, options: $0.1) }
    }()

    private static let passTypePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b(settimanale|quindicinale|mensile|trimestrale|semestrale|annuale)\b"#,
        options: .caseInsensitive
    )

    /// Tried in order, most specific first. The gap is `[^0-9]` rather than a
    /// list of allowed characters so a euro sign, colon, parenthesis, currency
    /// word or non-breaking space between the label and the amount can't break
    /// the match — the previous character class silently failed on any of those.
    private static let pricePatterns: [NSRegularExpression] = [
        #"importo\s+totale[^0-9]{0,30}([0-9]{1,5}[.,][0-9]{2})"#,
        #"totale[^0-9]{0,30}([0-9]{1,5}[.,][0-9]{2})"#,
        #"(?:importo|prezzo|amount|price)[^0-9]{0,30}([0-9]{1,5}[.,][0-9]{2})"#,
        #"€\s*([0-9]{1,5}[.,][0-9]{2})"#,
        #"([0-9]{1,5}[.,][0-9]{2})\s*€"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    // MARK: - Methods

    /// Fast parse used during mailbox sync (no Vision — mirrors Python).
    static func parse(pdfData: Data) -> ParsedPassPDF? {
        guard let document = PDFDocument(data: pdfData) else { return nil }

        var text = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            text += (page.string ?? "") + "\n"
        }

        guard let (start, end) = parseDates(in: text) else { return nil }
        let name = parsePassType(in: text, start: start, end: end)
        let qrData = extractQR(from: pdfData, document: document) ?? Data()
        let price = parsePrice(in: text)

        return ParsedPassPDF(
            name: name,
            startDate: start,
            endDate: end,
            qrImageData: qrData,
            price: price
        )
    }

    /// Prefer embedded square DCT image (like PyMuPDF get_images); else geometric crop.
    private static func extractQR(from pdfData: Data, document: PDFDocument) -> Data? {
        if let embedded = largestSquareEmbeddedJPEG(in: pdfData) {
            return embedded
        }
        return geometricQRCrop(from: document.page(at: 0))
    }

    private static func largestSquareEmbeddedJPEG(in pdfData: Data) -> Data? {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1),
              let dictionary = page.dictionary else { return nil }

        var resourcesObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "Resources", &resourcesObject),
              let resourcesObject else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(resourcesObject, .dictionary, &resources),
              let resources else { return nil }

        var xObjectObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(resources, "XObject", &xObjectObject),
              let xObjectObject else { return nil }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(xObjectObject, .dictionary, &xObjects),
              let xObjects else { return nil }

        var best: (area: Int, png: Data)?
        CGPDFDictionaryApplyBlock(xObjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else { return true }

            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                  let subtype,
                  String(cString: subtype) == "Image" else { return true }

            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
            guard width >= 80, height >= 80 else { return true }
            let ratio = Double(width) / Double(height)
            guard (0.85...1.15).contains(ratio) else { return true }

            var format = CGPDFDataFormat.raw
            guard let cfData = CGPDFStreamCopyData(stream, &format) else { return true }
            guard let png = pngData(fromImageData: cfData as Data) else { return true }

            let area = Int(width * height)
            if best == nil || area > best!.area {
                best = (area, png)
            }
            return true
        }, nil)

        return best?.png
    }

    private static func pngData(fromImageData data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    /// Fallback matching Python `_heuristic_qr_crop` (right side, upper band).
    private static func geometricQRCrop(from page: PDFPage?) -> Data? {
        guard let page else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3
        let side = min(bounds.width, bounds.height) * 0.42
        var left = bounds.width * 0.55
        // PDF y grows upward; Python crops from top of the bitmap (y≈0.12 from top).
        var bottom = bounds.height * (1.0 - 0.12 - 0.42)
        if left + side > bounds.width { left = bounds.width - side }
        if bottom < 0 { bottom = 0 }
        if bottom + side > bounds.height { bottom = bounds.height - side }

        let crop = CGRect(x: left, y: bottom, width: side, height: side)
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        return image.pngData()
    }

    private static func parseDates(in text: String) -> (Date, Date)? {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let range = NSRange(compact.startIndex..., in: compact)

        for pattern in datePatterns {
            guard let match = pattern.firstMatch(in: compact, range: range),
                  match.numberOfRanges >= 3,
                  let startRange = Range(match.range(at: 1), in: compact),
                  let endRange = Range(match.range(at: 2), in: compact),
                  let start = parseItalianDate(String(compact[startRange])),
                  let end = parseItalianDate(String(compact[endRange])) else { continue }
            // Skip accidental birthdate / emission pairings when span is nonsense.
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            if days < 0 || days > 400 { continue }
            return normalizedDatePair(start: start, end: end)
        }
        return nil
    }

    private static func normalizedDatePair(start: Date, end: Date) -> (Date, Date) {
        if start <= end { return (start, end) }
        return (end, start)
    }

    private static func parsePrice(in text: String) -> String {
        // collapse every kind of space, including the non-breaking ones PDFKit emits
        let compact = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let full = NSRange(compact.startIndex..., in: compact)

        for pattern in pricePatterns {
            guard let match = pattern.firstMatch(in: compact, range: full),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: compact) else { continue }
            let raw = String(compact[range]).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(raw) else { continue }
            return String(format: "%.2f €", value)
        }
        return ""
    }

    private static func parseItalianDate(_ raw: String) -> Date? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "/")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        for format in ["dd/MM/yyyy", "dd/MM/yy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func parsePassType(in text: String, start: Date, end: Date) -> String {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let range = NSRange(compact.startIndex..., in: compact)
        if let pattern = passTypePattern,
           let match = pattern.firstMatch(in: compact, range: range),
           let typeRange = Range(match.range(at: 1), in: compact) {
            return localizedPassType(from: String(compact[typeRange]))
        }

        let days = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        if days <= 14 { return String(localized: "Weekly") }
        if days <= 60 { return String(localized: "Monthly") }
        return String(localized: "Annual")
    }

    private static func localizedPassType(from raw: String) -> String {
        switch raw.lowercased() {
        case "settimanale", "quindicinale":
            return String(localized: "Weekly")
        case "mensile":
            return String(localized: "Monthly")
        case "trimestrale", "semestrale", "annuale":
            return String(localized: "Annual")
        default:
            return String(localized: "Monthly")
        }
    }
}
