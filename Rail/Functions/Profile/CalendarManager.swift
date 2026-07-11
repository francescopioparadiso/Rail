import Foundation
import EventKit
import SwiftData

class CalendarManager {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()
    
    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            print("Error requesting calendar access: \(error)")
            return false
        }
    }
    
    func syncTrainEvent(train: Train, stops: [Stop], seats: [Seat], titleFormat: String, calendarIdentifier: String? = nil, travelTime: TimeInterval = 0) async {
        guard await requestAccess() else { return }
        
        let trainStops = stops.filter { $0.id == train.id }.sorted(by: { $0.ref_time < $1.ref_time })
        let selectedStops = trainStops.filter { $0.is_selected }
        
        guard let firstStop = selectedStops.first, let lastStop = selectedStops.last else { return }
        
        let event: EKEvent
        if let identifier = train.calendarEventIdentifier, let existingEvent = eventStore.event(withIdentifier: identifier) {
            // Check if calendar has changed
            if let targetID = calendarIdentifier, !targetID.isEmpty, existingEvent.calendar.calendarIdentifier != targetID {
                // Calendar changed, we need to remove old and create new
                try? eventStore.remove(existingEvent, span: .thisEvent)
                event = EKEvent(eventStore: eventStore)
                if let calendar = eventStore.calendar(withIdentifier: targetID) {
                    event.calendar = calendar
                } else {
                    event.calendar = eventStore.defaultCalendarForNewEvents
                }
            } else {
                event = existingEvent
            }
        } else {
            event = EKEvent(eventStore: eventStore)
            
            if let targetID = calendarIdentifier, !targetID.isEmpty, let calendar = eventStore.calendar(withIdentifier: targetID) {
                event.calendar = calendar
            } else {
                event.calendar = eventStore.defaultCalendarForNewEvents
            }
        }
        
        // Title
        event.title = calendarTitle(
            for: train,
            firstStop: firstStop,
            seats: seats,
            titleFormat: titleFormat
        )
        
        // Date
        event.startDate = firstStop.dep_time_eff
        event.endDate = lastStop.arr_time_eff
        
        // Travel Time
        if event.responds(to: NSSelectorFromString("setTravelTime:")) {
            event.setValue(travelTime > 0 ? travelTime : 0, forKey: "travelTime")
        }
        
        // Location
        event.location = firstStop.name
        
        // Notes
        var notes = NSLocalizedString("Train details:", comment: "") + "\n"
        notes += "- \(train.logo) \(train.number)\n"
        notes += "- " + NSLocalizedString("Departure:", comment: "") + " \(firstStop.name) \(firstStop.dep_time_eff.formatted(Date.FormatStyle.dateTime.hour().minute()))\n"
        notes += "- " + NSLocalizedString("Arrival:", comment: "") + " \(lastStop.name) \(lastStop.arr_time_eff.formatted(Date.FormatStyle.dateTime.hour().minute()))\n"
        notes += "- " + NSLocalizedString("Stops:", comment: "") + " \(selectedStops.count)\n"
        
        let duration = lastStop.arr_time_eff.timeIntervalSince(firstStop.dep_time_eff)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let travelTimeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        notes += "- " + NSLocalizedString("Travel time:", comment: "") + " \(travelTimeString)\n"
        
        let distance = distance_between_stations(from: firstStop.name, to: lastStop.name) ?? 0
        if distance > 0 {
            notes += "- " + NSLocalizedString("Travel distance:", comment: "") + " \(distance) km\n"
        }
        
        notes += "\n"
        
        if !seats.isEmpty {
            notes += String(format: NSLocalizedString("Tickets (%lld)", comment: ""), seats.count) + ":\n"
            for seat in seats {
                var seatInfo = ""
                if !seat.carriage.isEmpty && !seat.number.isEmpty {
                    seatInfo += "\(seat.carriage)-\(seat.number)-\(seat.name)"
                } else {
                    seatInfo += "\(seat.name)"
                }
                notes += seatInfo + "\n"
            }
        } else {
            notes += NSLocalizedString("No tickets added.", comment: "")
        }
        event.notes = notes
        
        do {
            try eventStore.save(event, span: .thisEvent)
            train.calendarEventIdentifier = event.eventIdentifier
        } catch {
            print("Error saving event: \(error)")
        }
    }
    
    func getCalendars() async -> [EKCalendar] {
        guard await requestAccess() else { return [] }
        return eventStore.calendars(for: .event).sorted(by: { $0.title < $1.title })
    }
    
    func getCalendar(with identifier: String) -> EKCalendar? {
        return eventStore.calendar(withIdentifier: identifier)
    }
    
    func removeTrainEvent(train: Train) async {
        guard await requestAccess() else { return }
        guard let identifier = train.calendarEventIdentifier, let event = eventStore.event(withIdentifier: identifier) else { return }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            train.calendarEventIdentifier = nil
        } catch {
            print("Error removing event: \(error)")
        }
    }
    
    func removeAllEvents(trains: [Train]) async {
        for train in trains {
            await removeTrainEvent(train: train)
        }
    }
    
    private func calendarTitle(for train: Train, firstStop: Stop, seats: [Seat], titleFormat: String) -> String {
        let localizedFormat = NSLocalizedString(titleFormat, comment: "")
        let needsSeatDetails = localizedFormat.contains("{carriage}")
        
        if needsSeatDetails {
            guard let firstSeat = seats.first,
                  !firstSeat.carriage.isEmpty,
                  !firstSeat.number.isEmpty else {
                return NSLocalizedString("Train", comment: "")
            }
            
            return localizedFormat
                .replacingOccurrences(of: "{logo}", with: train.logo)
                .replacingOccurrences(of: "{direction}", with: train.direction)
                .replacingOccurrences(of: "{first_stop}", with: firstStop.name)
                .replacingOccurrences(of: "{carriage}", with: firstSeat.carriage)
                .replacingOccurrences(of: "{number}", with: firstSeat.number)
        }
        
        return localizedFormat
            .replacingOccurrences(of: "{logo}", with: train.logo)
            .replacingOccurrences(of: "{direction}", with: train.direction)
            .replacingOccurrences(of: "{first_stop}", with: firstStop.name)
            .replacingOccurrences(of: "{number}", with: train.number)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
