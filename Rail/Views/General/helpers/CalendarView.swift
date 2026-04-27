import SwiftUI
import SwiftData
import EventKit

struct CalendarView: View {
    // MARK: - variables
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    
    @AppStorage("calendarTitleFormat") private var titleFormat: String = "Train {number}"
    @AppStorage("selectedCalendarIdentifier") private var selectedCalendarIdentifier: String = ""
    @AppStorage("autoSyncToCalendar") private var autoSyncToCalendar: Bool = true
    @AppStorage("calendarTravelTime") private var travelTime: Double = 0 // in seconds
    
    @State private var availableCalendars: [EKCalendar] = []
    @State private var isAuthorized: Bool = CalendarManager.shared.isAuthorized
    @State private var showPermissionAlert: Bool = false
    
    private var selectedCalendarTitle: String {
        if selectedCalendarIdentifier.isEmpty {
            return "Default"
        }
        return availableCalendars.first(where: { $0.calendarIdentifier == selectedCalendarIdentifier })?.title ?? "Default"
    }
    
    private var travelTimeTitle: String {
        if travelTime == 0 { return NSLocalizedString("None", comment: "") }
        let minutes = Int(travelTime / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            if hours == 1 {
                return NSLocalizedString("1 hour", comment: "")
            } else {
                return String(format: NSLocalizedString("%lld hours", comment: ""), hours)
            }
        }
        if minutes == 1 {
            return NSLocalizedString("1 minute", comment: "")
        } else {
            return String(format: NSLocalizedString("%lld minutes", comment: ""), minutes)
        }
    }

    // MARK: - main content
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Add to calendar automatically", isOn: Binding(
                        get: { autoSyncToCalendar },
                        set: { newValue in
                            autoSyncToCalendar = newValue
                            if newValue {
                                resyncAll()
                            } else {
                                removeAll()
                            }
                        }
                    ))
                    .fontDesign(app_font_design)
                    
                    HStack {
                        Text("Calendar")
                        Spacer()
                        Menu {
                            Button {
                                selectedCalendarIdentifier = ""
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("Default")
                                    if selectedCalendarIdentifier.isEmpty {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                                Button {
                                    selectedCalendarIdentifier = cal.calendarIdentifier
                                    resyncAll()
                                } label: {
                                    HStack {
                                        Text(cal.title)
                                        if selectedCalendarIdentifier == cal.calendarIdentifier {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(selectedCalendarTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Preferences") {
                    HStack {
                        Text("Title Format")
                        Spacer()
                        Menu {
                            Button {
                                titleFormat = "Train"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("Train")
                                    if titleFormat == "Train" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                titleFormat = "Train {number}"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("Train 9808")
                                    if titleFormat == "Train {number}" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                titleFormat = "🚄 Train"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("🚄 Train")
                                    if titleFormat == "🚄 Train" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button {
                                titleFormat = "🚂 Train"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("🚂 Train")
                                    if titleFormat == "🚂 Train" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button {
                                titleFormat = "🚉 Train"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("🚉 Train")
                                    if titleFormat == "🚉 Train" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                titleFormat = "Train {carriage}/{number}"
                                resyncAll()
                            } label: {
                                HStack {
                                    Text("Train 1/15A")
                                    if titleFormat == "Train {carriage}/{number}" {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Text(String(localized: String.LocalizationValue(titleFormat))
                                .replacingOccurrences(of: "{carriage}", with: "1")
                                .replacingOccurrences(of: "{number}", with: titleFormat.contains("{carriage}") ? "15A" : "9808"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Travel time")
                        Spacer()
                        Menu {
                            ForEach([0, 15, 30, 45, 60, 120], id: \.self) { mins in
                                Button {
                                    travelTime = Double(mins * 60)
                                    resyncAll()
                                } label: {
                                    HStack {
                                        if mins == 0 {
                                            Text("None")
                                        } else if mins >= 60 {
                                            let hours = mins / 60
                                            if hours == 1 {
                                                Text("1 hour")
                                            } else {
                                                Text("\(hours) hours")
                                            }
                                        } else {
                                            if mins == 1 {
                                                Text("1 minute")
                                            } else {
                                                Text("\(mins) minutes")
                                            }
                                        }
                                        
                                        if Int(travelTime / 60) == mins {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(travelTimeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .fontDesign(app_font_design)
            .onAppear {
                Task {
                    if isAuthorized {
                        availableCalendars = await CalendarManager.shared.getCalendars()
                    } else {
                        let granted = await CalendarManager.shared.requestAccess()
                        await MainActor.run {
                            withAnimation {
                                isAuthorized = granted
                            }
                            if !granted {
                                showPermissionAlert = true
                            }
                        }
                        if granted {
                            availableCalendars = await CalendarManager.shared.getCalendars()
                        }
                    }
                }
            }
            .alert("Calendar Access Required", isPresented: $showPermissionAlert) {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { 
                    dismiss()
                }
            } message: {
                Text("Rail needs access to your calendar to add train journeys as events. Please enable it in Settings.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .disabled(!isAuthorized)
        }
    }
    
    private func resyncAll() {
        guard isAuthorized && autoSyncToCalendar else { return }
        Task {
            for train in trains {
                let trainStops = stops.filter { $0.id == train.id }
                let trainSeats = seats.filter { $0.trainID == train.id }
                await CalendarManager.shared.syncTrainEvent(
                    train: train,
                    stops: trainStops,
                    seats: trainSeats,
                    titleFormat: titleFormat,
                    calendarIdentifier: selectedCalendarIdentifier,
                    travelTime: travelTime
                )
            }
        }
    }
    
    private func removeAll() {
        guard isAuthorized else { return }
        Task {
            await CalendarManager.shared.removeAllEvents(trains: trains)
        }
    }
}
