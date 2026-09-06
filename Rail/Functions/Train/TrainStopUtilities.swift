import Foundation

// Roman to Arabic numeral conversion
func romanToArabic(platform: String) -> String {
    let roman = ["XX", "XIX", "XVIII", "XVII", "XVI", "XV", "XIV", "XIII", "XII", "XI", "X", "IX", "VIII", "VII", "VI", "V", "IV", "III", "II", "I"]
    let arabic = ["20", "19", "18", "17", "16", "15", "14", "13", "12", "11", "10", "9", "8", "7", "6", "5", "4", "3", "2", "1"]

    let parts = platform.split(separator: " ")
    if parts.count < 2 {
        if platform == "-" || platform.allSatisfy({ $0.isNumber }) {
            return platform
        } else {
            var result = platform
            let sortedPairs = zip(roman, arabic)
            for (romanNumeral, arabicNumeral) in sortedPairs {
                result = result.replacingOccurrences(of: romanNumeral, with: arabicNumeral)
            }
            return result
        }
    } else {
        var firstPart = String(parts[0])
        let secondPart = String(parts[1])

        let sortedPairs = zip(roman, arabic)
        for (romanNumeral, arabicNumeral) in sortedPairs {
            firstPart = firstPart.replacingOccurrences(of: romanNumeral, with: arabicNumeral)
        }

        if secondPart == "TR" {
            return firstPart + " /"
        } else {
            return firstPart + " " + secondPart
        }
    }
}

// MARK: - Run window of a fetched train

/// The first usable date under `keys`, skipping the placeholders the APIs leave
/// behind when a time is missing.
private nonisolated func stopDate(in stop: [String: Any], keys: [String]) -> Date? {
    for key in keys {
        guard let date = stop[key] as? Date else { continue }
        guard date != .distantPast, date.timeIntervalSince1970 > 0 else { continue }
        return date
    }
    return nil
}

/// When a fetched train leaves its first stop and reaches its last one.
private nonisolated func trainRunWindow(info: [String: Any]) -> (departure: Date, arrival: Date)? {
    let stops = info["stops"] as? [[String: Any]] ?? []
    guard let firstStop = stops.first, let lastStop = stops.last,
          let departure = stopDate(in: firstStop, keys: ["dep_time_eff", "dep_time_id", "ref_time"]),
          let arrival = stopDate(in: lastStop, keys: ["arr_time_eff", "arr_time_id", "ref_time"])
    else { return nil }

    return (departure, arrival)
}

/// Whether a fetched train is still worth offering to add.
///
/// A train that left ten minutes ago is one you may well be sitting on, so today's
/// runs stay addable however late you look them up. Only a run that both departed
/// and arrived before today — yesterday's train, over and done with — is dropped;
/// an overnight service that left yesterday and lands this morning is kept.
nonisolated func isTrainAddable(info: [String: Any], now: Date = Date()) -> Bool {
    guard let window = trainRunWindow(info: info) else { return true }
    let startOfToday = Calendar.current.startOfDay(for: now)
    return window.departure >= startOfToday || window.arrival >= startOfToday
}
