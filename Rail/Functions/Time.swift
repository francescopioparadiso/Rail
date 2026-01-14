import Foundation

func adjust_date(actual_date: Date, previous_date: Date?, selected_date: Date) -> Date {
    let calendar = Calendar.current
    // map actual time (hour/minute) onto the selected_date
    let hour = calendar.component(.hour, from: actual_date)
    let minute = calendar.component(.minute, from: actual_date)
    var current = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selected_date)!
    
    // if no previous adjusted date -> base on selected_date
    guard let previousAdjusted = previous_date else {
        return current
    }
    
    // if current is not strictly after previousAdjusted, add days until it is
    while current <= previousAdjusted {
        current = calendar.date(byAdding: .day, value: 1, to: current)!
    }
    
    return current
}

func time_to_date(timeString: String) -> Date? {
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
