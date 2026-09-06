import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    // MARK: - Properties

    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var passes: [Pass]

    @State private var showPermissionAlert: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                Toggle("Allow notifications", isOn: notificationBinding(\.isEnabled).animation())
                    .onChange(of: profile.resolvedNotificationSettings.isEnabled) { _, newValue in
                        if newValue { enableAlerts() } else { removeAll() }
                    }
            } footer: {
                Text("Alerts are scheduled on this device from the times Rail last saw. Open the app to pick up new delays.")
            }

            if profile.resolvedNotificationSettings.isEnabled {
                Section {
                    Picker("Departure", selection: notificationBinding(\.departureLead)) {
                        leadOptions
                    }
                    .onChange(of: profile.resolvedNotificationSettings.departureLead) { _, _ in
                        resyncAll()
                    }

                    Picker("Arrival", selection: notificationBinding(\.arrivalLead)) {
                        leadOptions
                    }
                    .onChange(of: profile.resolvedNotificationSettings.arrivalLead) { _, _ in
                        resyncAll()
                    }
                } header: {
                    Text("Journeys")
                }

                Section {
                    HStack {
                        Text("Before expiry")

                        Spacer(minLength: 12)

                        TextField(
                            "0",
                            value: notificationBinding(\.passLeadValue),
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 56)

                        Picker("", selection: notificationBinding(\.passLeadUnit)) {
                            Text("days").tag(NotificationSettings.PassLeadUnit.days)
                            Text("weeks").tag(NotificationSettings.PassLeadUnit.weeks)
                        }
                        .labelsHidden()
                    }
                    .onChange(of: profile.resolvedNotificationSettings.passLeadDays) { _, _ in
                        resyncAll()
                    }
                } header: {
                    Text("Passes")
                } footer: {
                    Text("Warnings arrive at 9 in the morning. A weekly pass cannot be warned about more than a week ahead, so it falls back to two days; anything up to a week applies to every pass.")
                }
            }
        }
        .navigationTitle("Notifications")
        .fontDesign(.rounded)
        .alert("Notification Access Required", isPresented: $showPermissionAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Rail needs permission to send notifications to warn you before a departure or an arrival. Please enable it in Settings.")
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var leadOptions: some View {
        Text("None").tag(Double(0))
        Text("5 minutes").tag(Double(300))
        Text("10 minutes").tag(Double(600))
        Text("15 minutes").tag(Double(900))
        Text("20 minutes").tag(Double(1200))
        Text("30 minutes").tag(Double(1800))
        Text("45 minutes").tag(Double(2700))
        Text("1 hour").tag(Double(3600))
        Text("2 hours").tag(Double(7200))
    }

    // MARK: - Actions

    private func notificationBinding<Value>(_ keyPath: WritableKeyPath<NotificationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { profile.resolvedNotificationSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = profile.resolvedNotificationSettings
                settings[keyPath: keyPath] = newValue
                profile.notificationSettings = settings
                try? modelContext.save()
            }
        )
    }

    private func enableAlerts() {
        Task {
            if await NotificationManager.shared.authorizationStatus() == .notDetermined {
                _ = await NotificationManager.shared.requestAccess()
            }

            guard await NotificationManager.shared.isAuthorized() else {
                showPermissionAlert = true
                return
            }

            await NotificationManager.shared.syncAlerts(
                trains: trains,
                stops: stops,
                passes: passes,
                settings: profile.resolvedNotificationSettings
            )
        }
    }

    private func resyncAll() {
        guard profile.resolvedNotificationSettings.isEnabled else { return }
        Task {
            await NotificationManager.shared.syncAlerts(
                trains: trains,
                stops: stops,
                passes: passes,
                settings: profile.resolvedNotificationSettings
            )
        }
    }

    private func removeAll() {
        Task {
            await NotificationManager.shared.removeAllAlerts()
        }
    }
}
