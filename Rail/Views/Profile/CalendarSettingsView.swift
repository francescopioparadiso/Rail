import SwiftUI
import SwiftData
import EventKit

struct CalendarSettingsView: View {
    // MARK: - Properties

    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    @State private var availableCalendars: [EKCalendar] = []
    @State private var isAuthorized: Bool = CalendarManager.shared.isAuthorized
    @State private var showPermissionAlert: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                Toggle("Add to calendar automatically", isOn: calendarBinding(\.autoSyncToCalendar).animation())
                    .onChange(of: profile.calendarSettings.autoSyncToCalendar) { _, newValue in
                        if newValue { resyncAll() } else { removeAll() }
                    }
            }
            .disabled(!isAuthorized)

            // Nothing below shapes an event until there are events to shape, and
            // switching the toggle off takes every one of them down.
            if profile.calendarSettings.autoSyncToCalendar {
                Section {
                    Picker("Calendar", selection: calendarBinding(\.calendarIdentifier)) {
                        Label { Text("Default") } icon: { dot(CalendarManager.shared.defaultCalendarColor) }
                            .tag("")
                        ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                            Label { Text(cal.title) } icon: { dot(cal.cgColor) }
                                .tag(cal.calendarIdentifier)
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
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle("Calendar")
        .fontDesign(appFontDesign)
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

    // MARK: - Subviews

    /// A filled circle in the calendar's colour. A picture rather than a symbol, so
    /// the menu keeps the colour instead of drawing it in one tint.
    private func dot(_ color: CGColor?) -> Image {
        // the picture is wider than the circle: the empty right side is the gap
        // between it and the name
        let size = CGSize(width: 18, height: 12)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(cgColor: color ?? UIColor.systemGray.cgColor).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 12, height: 12)).fill()
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    // MARK: - Actions

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
