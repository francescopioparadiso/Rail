import Foundation

/// Month heading for a list section: "Marzo" within the current year, "Marzo 2024"
/// otherwise. Used by the past-trains, passes and both email-import lists.
nonisolated func monthSectionTitle(for date: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        ? "LLLL" : "LLLL yyyy"
    return formatter.string(from: date).capitalized
}

func timeToDate(timeString: String) -> Date? {
    if timeString == "" || timeString == "01:00" {
        return .distantPast
    }
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm"
    timeFormatter.locale = Locale(identifier: "it_IT_POSIX")
    timeFormatter.timeZone = TimeZone(secondsFromGMT: 3600) // Interpret time string in GMT
    
    let time = timeFormatter.date(from: timeString.trimmingCharacters(in: .whitespaces))
    
    let calendar = Calendar.current
    let now = Date()
    
    let hour = calendar.component(.hour, from: time!)
    let minute = calendar.component(.minute, from: time!)
    
    if let todayWithTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) {
        return todayWithTime
    } else {
        return nil
    }
}
