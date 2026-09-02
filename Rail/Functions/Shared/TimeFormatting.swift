import Foundation

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
