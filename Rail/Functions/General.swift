import Foundation
import SwiftUI
import StoreKit

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

        // Only convert the first part
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

// Compare two stops
func stopsEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    let nameA = a["name"] as? String
    let nameB = b["name"] as? String
    let timeA = a["ref_time"] as? Date
    let timeB = b["ref_time"] as? Date
    return nameA == nameB && timeA == timeB
}

//

// App review manager
@MainActor
class ReviewManager {
    static let shared = ReviewManager()
    
    private init() {}
    
    func requestReviewIfAppropriate(action: RequestReviewAction) {
        // 1. get current count
        let currentCount = UserDefaults.standard.integer(forKey: "appLaunchCount")
        
        // 2. increment count
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: "appLaunchCount")
        
        print("📊 Interazioni totali: \(newCount)")
        
        // 3. define significant interaction points
        let significantInteractions = [5, 10, 20, 30, 50, 75, 100, 200, 300, 500, 1000]
        
        // 4. check if new count is significant
        if significantInteractions.contains(newCount) {
            print("🌟 Richiesta recensione avviata...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                action()
            }
        }
    }
}

// Get stop names for a station
func get_stop_names(for station: String) async -> [String] {
    guard let filePath = Bundle.main.path(forResource: "stations", ofType: "csv") else {
        print("❌ Error: stations.csv not found in bundle")
        return []
    }

    var names_list: [String] = []
    
    do {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let rows = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            if columns[2].contains("|") {
                if columns[2].split(separator: "|").contains(where: { $0 == station.lowercased() }) {
                    for name in columns[2].split(separator: "|") {
                        names_list.append(String(name))
                    }
                }
            } else {
                if columns[2] == station.lowercased() {
                    names_list.append(columns[2])
                }
            }
        }
    } catch {
        print("❌ Error reading CSV file: \(error)")
    }
    
    return names_list
}
