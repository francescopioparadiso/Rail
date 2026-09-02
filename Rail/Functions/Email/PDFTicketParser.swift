import Foundation
import PDFKit

enum PDFTicketParser {
    static func parse(pdfData: Data) -> [EmailContentPassenger] {
        guard let document = PDFDocument(data: pdfData) else { return [] }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        
        let qrData = extractQR(from: pdfData, document: document) ?? Data()
        
        let names = allMatchesGroups(in: text, pattern: #"(?:Passeggero|Nominativo|Name)[\s:]*([A-Za-zÀ-ÿ\s']{2,40}?)(?:\n|\r|Carta|Tariffa|CP|Biglietto|Codice|Data|Type)"#).map { $0.groups[0].trimmingCharacters(in: .whitespacesAndNewlines) }
        
        let coaches = allMatchesGroups(in: text, pattern: #"(?:Carrozza|Coach)[\s:]*(\d+)"#).map { Int($0.groups[0]) ?? 0 }
        
        let seats = allMatchesGroups(in: text, pattern: #"(?:Posto|Seat)[\s:]*([0-9A-Z]+)"#).map { $0.groups[0] }
        
        let count = max(1, max(names.count, max(coaches.count, seats.count)))
        
        var passengers: [EmailContentPassenger] = []
        for i in 0..<count {
            let name = i < names.count ? names[i] : ""
            let coach = i < coaches.count ? coaches[i] : 0
            let seat = i < seats.count ? seats[i] : ""
            passengers.append(EmailContentPassenger(name: name, carriage: coach, seat: seat, qrcode: qrData))
        }
        
        return passengers
    }
    
    private static func allMatchesGroups(in text: String, pattern: String) -> [(groups: [String], range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let fullRange = Range(match.range, in: text) else { return nil }
            let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
                return String(text[captureRange])
            }
            return (groups, fullRange)
        }
    }
    
    // Copy extractQR from PassPDFParser
    private static func extractQR(from pdfData: Data, document: PDFDocument) -> Data? {
        if let embedded = largestSquareEmbeddedJPEG(in: pdfData) {
            return embedded
        }
        return nil
    }
    
    private static func largestSquareEmbeddedJPEG(in pdfData: Data) -> Data? {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1),
              let dictionary = page.dictionary else { return nil }

        var resourcesObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "Resources", &resourcesObject),
              let resourcesObj = resourcesObject else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(resourcesObj, .dictionary, &resources),
              let res = resources else { return nil }

        var xObjectObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(res, "XObject", &xObjectObject),
              let xObjObj = xObjectObject else { return nil }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(xObjObj, .dictionary, &xObjects),
              let xObjs = xObjects else { return nil }

        var bestData: Data?
        var bestSize: Int = 0

        CGPDFDictionaryApplyBlock(xObjs, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream = stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else { return true }

            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                  let subtypeName = subtype,
                  String(cString: subtypeName) == "Image" else { return true }

            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)

            var format = CGPDFDataFormat.raw
            guard let cfData = CGPDFStreamCopyData(stream, &format) else { return true }
            let data = cfData as Data

            // We look for a roughly square image (QR/Aztec) that's reasonably large
            if width > 50 && height > 50 && abs(width - height) < 20 {
                if data.count > bestSize {
                    bestSize = data.count
                    bestData = data
                }
            }
            return true
        }, nil)

        return bestData
    }
}
