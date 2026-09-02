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
