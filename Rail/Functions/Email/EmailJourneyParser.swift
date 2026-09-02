import Foundation

enum EmailJourneyParser {
    struct ParsedJourney {
        let departureDate: Date
        let arrivalDate: Date?
        let trainNumber: String
        let departureStation: String
        let arrivalStation: String
        let price: String
    }

    nonisolated static func parse(from body: String) -> ParsedJourney? {
        let text = normalize(body)
        
        var trainNumber = ""
        var journeyDateStr = ""
        var depStation = ""
        var depTime = ""
        var arrStation = ""
        var arrTime = ""
        
        let numericDatePattern = #"\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})"#
        let monthDatePattern = #"\d{1,2}\s+[A-Za-zÀ-ÿ]+\s+\d{4}"#
        let datePattern = #"(?:\#(numericDatePattern)|\#(monthDatePattern))"#

        let trainPatterns = [
            #"(?i)(\d{1,6})\s+(?:del|data|of|on)\s+(\#(datePattern))"#,
            #"(?i)(?:treno|train|frecciarossa|frecciargento|frecciabianca|intercity|regionale)[^0-9]{0,30}(\d{1,6}).{0,100}?(?:data(?:\s+(?:partenza|viaggio))?|partenza|departure(?:\s+date)?)[^0-9A-Za-zÀ-ÿ]{0,20}(\#(datePattern))"#,
            #"(?i)(?:data(?:\s+(?:partenza|viaggio))?|partenza|departure(?:\s+date)?)[^0-9A-Za-zÀ-ÿ]{0,20}(\#(datePattern)).{0,100}?(?:treno|train|frecciarossa|frecciargento|frecciabianca|intercity|regionale)[^0-9]{0,30}(\d{1,6})"#
        ]

        for (index, pattern) in trainPatterns.enumerated() {
            guard let match = firstMatch(in: text, pattern: pattern), match.groups.count >= 2 else { continue }
            if index == 2 {
                journeyDateStr = match.groups[0]
                trainNumber = match.groups[1]
            } else {
                trainNumber = match.groups[0]
                journeyDateStr = match.groups[1]
            }
            print("[PARSER-DEBUG] train regex matched: number=\(trainNumber) date=\(journeyDateStr)")
            break
        }

        if trainNumber.isEmpty || journeyDateStr.isEmpty {
            print("[PARSER-DEBUG] train regex DID NOT match")
            if let delRange = text.range(of: "del ", options: .caseInsensitive) {
                let start = text.index(delRange.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(delRange.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
                print("[PARSER-DEBUG] context around 'del': ...\(text[start..<end])...")
            }
        }
        

        let m2Matches = allMatchesGroups(in: text, pattern: #"([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,60}?)\s*\(\s*(?:ore|time)?\s*:?\s*(\d{1,2}:\d{2})\s*\)\s*[-–—]\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,60}?)\s*\(\s*(?:ore|time)?\s*:?\s*(\d{1,2}:\d{2})\s*\)"#)
        let m3Matches = allMatchesGroups(in: text, pattern: #"(?i)(?:da|from)\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,60}?)\s+(?:\(?\s*(?:ore|time)\s*:?\s*)?(\d{1,2}:\d{2})\s*\)?.{0,80}?(?:a|to)\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,60}?)\s+(?:\(?\s*(?:ore|time)\s*:?\s*)?(\d{1,2}:\d{2})\s*\)?"#)
        let m4Matches = allMatchesGroups(in: text, pattern: #"(?i)(?:stazione\s+di\s+partenza|partenza|departure):?\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,80}?)\s+(?:orario|ore|time)?\s*:?\s*(\d{1,2}:\d{2}).{0,120}?(?:stazione\s+di\s+arrivo|arrivo|arrival):?\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 .'’-]{1,80}?)\s+(?:orario|ore|time)?\s*:?\s*(\d{1,2}:\d{2})"#)
        let m5Matches = allMatchesGroups(in: text, pattern: #"(?i)(?:Partenza|Departure):?\s+(.+?)\s+(?:\(?\s*(?:ore|time)\s*:?\s*)?(\d{1,2}:\d{2})\s*\)?.{0,80}?(?:Arrivo|Arrival):?\s+(.+?)\s+(?:\(?\s*(?:ore|time)\s*:?\s*)?(\d{1,2}:\d{2})\s*\)?"#)

        let bestMatches: [(groups: [String], range: Range<String.Index>)]
        if !m2Matches.isEmpty { bestMatches = m2Matches }
        else if !m3Matches.isEmpty { bestMatches = m3Matches }
        else if !m4Matches.isEmpty { bestMatches = m4Matches }
        else if !m5Matches.isEmpty { bestMatches = m5Matches }
        else { bestMatches = [] }

        if let first = bestMatches.first, let last = bestMatches.last, first.groups.count >= 4, last.groups.count >= 4 {
            depStation = first.groups[0].trimmingCharacters(in: .whitespacesAndNewlines)
            depTime = first.groups[1]
            arrStation = last.groups[2].trimmingCharacters(in: .whitespacesAndNewlines)
            arrTime = last.groups[3]
            print("[PARSER-DEBUG] station regex matched: \(depStation)(\(depTime)) -> \(arrStation)(\(arrTime))")
        } else {
            print("[PARSER-DEBUG] NO station regex matched")
        }

        
        var priceVal = 0.0
        var foundPrice = false

        // Only the first "importo" counts. Confirmation emails repeat the amount
        // per leg, per passenger and again as a total, and the HTML part is often
        // duplicated below the plain-text part — summing them multiplies the fare.
        let fareMatches = allMatches(in: text, pattern: #"(?i)\b(?:importo|amount)\b(?:[^0-9]{0,40})?(\d+[,.]\d{2})"#)
            ?? allMatches(in: text, pattern: #"(?i)\b(?:prezzo|price)\b[^0-9]{0,20}(\d+[,.]\d{2})"#)
        if let first = fareMatches?.first,
           let val = Double(first.replacingOccurrences(of: ",", with: ".")) {
            priceVal += val
            foundPrice = true
        }

        if let postoMatches = allMatches(in: text, pattern: #"(?i)\b(?:scelta(?: del)? posto|seat selection)\b(?:[^0-9]{0,100})?(\d+[,.]\d{2})"#) {
            // one charge per passenger, so these do add up
            for matchStr in postoMatches {
                let numStr = matchStr.replacingOccurrences(of: ",", with: ".")
                guard let val = Double(numStr) else { continue }
                priceVal += val
                foundPrice = true
            }
        }
        
        let price = foundPrice ? String(format: "%.2f €", priceVal) : "Unknown"

        guard !trainNumber.isEmpty, !journeyDateStr.isEmpty, !depStation.isEmpty else {
            print("[PARSER-DEBUG] FAILED: trainNumber=\(trainNumber.isEmpty ? "empty" : trainNumber) date=\(journeyDateStr.isEmpty ? "empty" : journeyDateStr) depStation=\(depStation.isEmpty ? "empty" : depStation)")
            return nil
        }

        let dateNormalized = journeyDateStr.replacingOccurrences(of: "-", with: "/")
        
        guard let departureDate = combine(date: dateNormalized, time: depTime) else {
            print("[PARSER-DEBUG] FAILED: could not combine date=\(dateNormalized) time=\(depTime)")
            return nil
        }
        
        print("[PARSER-DEBUG] SUCCESS: train=\(trainNumber) \(depStation)(\(depTime)) -> \(arrStation)(\(arrTime)) price=\(price)")
        return ParsedJourney(
            departureDate: departureDate,
            arrivalDate: arrivalDate(on: dateNormalized, time: arrTime, after: departureDate),
            trainNumber: trainNumber,
            departureStation: depStation,
            arrivalStation: arrStation,
            price: price
        )
    }

    nonisolated private static func arrivalDate(on date: String, time: String, after departureDate: Date) -> Date? {
        guard let arrival = combine(date: date, time: time) else { return nil }
        if arrival < departureDate {
            return Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: arrival)
        }
        return arrival
    }

    nonisolated private static func window(after range: Range<String.Index>, in text: String, maxLength: Int) -> String {
        let start = range.upperBound
        let end = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }

    nonisolated private static func allMatches(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty { return nil }
        
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    nonisolated private static func firstMatch(
        in text: String,
        pattern: String
    ) -> (groups: [String], range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let fullRange = Range(match.range, in: text) else { return nil }

        let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
            guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[captureRange])
        }
        return (groups, fullRange)
    }

    nonisolated private static func normalize(_ text: String) -> String {
        var result = text
        for separator in [
            "\u{00A0}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{202F}",
            "&nbsp;", "&#160;", "&#xA0;",
            "\u{00E2}\u{0080}\u{0089}", // Mojibake for Thin Space
            "\u{00C2}\u{00A0}"         // Mojibake for NBSP
        ] {
            result = result.replacingOccurrences(of: separator, with: " ", options: .caseInsensitive)
        }
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</td>", "</tr>", "</strong>", "</span>"] {
            result = result.replacingOccurrences(of: tag, with: " ", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        // Flatten CR/LF/tabs/thin spaces into single spaces for reliable regex matching.
        result = result.replacingOccurrences(of: #"[\r\n\t\f]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func combine(date: String, time: String) -> Date? {
        let normalizedDate = date
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "dd/MM/yyyy HH:mm",
            "d/M/yyyy HH:mm",
            "dd/MM/yy HH:mm",
            "d/M/yy HH:mm",
            "dd-MM-yyyy HH:mm",
            "d-M-yyyy HH:mm",
            "d MMMM yyyy HH:mm",
            "dd MMMM yyyy HH:mm"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.twoDigitStartDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000))!
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: "\(normalizedDate) \(normalizedTime)") {
                return parsed
            }
        }
        return nil
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

    nonisolated private static func allMatchesGroups(
        in text: String,
        pattern: String
    ) -> [(groups: [String], range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
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
}
