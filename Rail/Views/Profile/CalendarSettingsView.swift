import SwiftUI
import SwiftData
import EventKit

struct CalendarSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    @State private var availableCalendars: [EKCalendar] = []
    @State private var isAuthorized: Bool = CalendarManager.shared.isAuthorized
    @State private var showPermissionAlert: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Add to calendar automatically", isOn: calendarBinding(\.autoSyncToCalendar))
                    .onChange(of: profile.calendarSettings.autoSyncToCalendar) { _, newValue in
                        if newValue { resyncAll() } else { removeAll() }
                    }

                Picker("Calendar", selection: calendarBinding(\.calendarIdentifier)) {
                    Text("Default").tag("")
                    ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal.calendarIdentifier)
                    }
                }
                .onChange(of: profile.calendarSettings.calendarIdentifier) { _, _ in
                    resyncAll()
                }

                Picker("Title Format", selection: calendarBinding(\.titleFormat)) {
                    Text("Train").tag("Train")
                    Text("Train 9808").tag("Train {number}")
                    Text("🚄 Train").tag("🚄 Train")
                    Text("🚂 Train").tag("🚂 Train")
                    Text("🚉 Train").tag("🚉 Train")
                    Text("Train 1/15A").tag("Train {carriage}/{number}")
                }
                .onChange(of: profile.calendarSettings.titleFormat) { _, _ in
                    resyncAll()
                }

                Picker("Travel time", selection: calendarBinding(\.travelTime)) {
                    Text("None").tag(Double(0))
                    Text("15 minutes").tag(Double(900))
                    Text("30 minutes").tag(Double(1800))
                    Text("45 minutes").tag(Double(2700))
                    Text("1 hour").tag(Double(3600))
                    Text("2 hours").tag(Double(7200))
                }
                .onChange(of: profile.calendarSettings.travelTime) { _, _ in
                    resyncAll()
                }
            }
            .disabled(!isAuthorized)
        }
        .navigationTitle("Calendar")
        .fontDesign(.rounded)
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
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Rail needs access to your calendar to add train journeys as events. Please enable it in Settings.")
        }
    }

    private func calendarBinding<Value>(_ keyPath: WritableKeyPath<CalendarSettings, Value>) -> Binding<Value> {
        Binding(
            get: { profile.calendarSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = profile.calendarSettings
                settings[keyPath: keyPath] = newValue
                profile.calendarSettings = settings
                try? modelContext.save()
            }
        )
    }

    private func resyncAll() {
        guard isAuthorized && profile.calendarSettings.autoSyncToCalendar else { return }
        let settings = profile.calendarSettings
        Task {
            for train in trains {
                let trainStops = stops.filter { $0.id == train.id }
                let trainSeats = seats.filter { $0.trainID == train.id }
                await CalendarManager.shared.syncTrainEvent(
                    train: train,
                    stops: trainStops,
                    seats: trainSeats,
                    titleFormat: settings.titleFormat,
                    calendarIdentifier: settings.calendarIdentifier,
                    travelTime: settings.travelTime
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
