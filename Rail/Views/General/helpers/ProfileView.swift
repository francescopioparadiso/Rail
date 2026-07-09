import SwiftUI
import SwiftData
import PhotosUI
import EventKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var showImagePicker = false
    @State private var profileImage: UIImage?
    @State private var formattedDelay = "0m"
    @State private var formattedDistance = "0 km"

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    profileForm(for: profile)
                } else {
                    ProgressView()
                }
            }
            .fontDesign(.rounded)
            .background(app_background_color)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .onAppear {
            if profiles.isEmpty {
                modelContext.insert(UserProfile())
                try? modelContext.save()
            }
        }
        .task(id: profile?.photo) {
            profileImage = profile?.photo.flatMap { UIImage(data: $0) }
            await loadStats()
        }
    }

    @ViewBuilder
    private func profileForm(for profile: UserProfile) -> some View {
        @Bindable var profile = profile

        Form {
            Section {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Button {
                            showImagePicker = true
                        } label: {
                            if let profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 160)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            } else {
                                Circle()
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                                    .frame(width: 160, height: 160)
                                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 60, height: 60)
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        .sheet(isPresented: $showImagePicker) {
                            ImagePicker(imageData: Binding(
                                get: { profile.photo },
                                set: { profile.photo = $0 }
                            ))
                        }

                        TextField("Name", text: $profile.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock.badge.exclamationmark")
                                Text("Delay")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            Text(formattedDelay)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(24)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "map")
                                Text("Distance")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            Text(formattedDistance)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(24)
                    }
                    .padding(.bottom, 10)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section(header: Text("Settings")) {
                NavigationLink {
                    CalendarSettingsView(profile: profile)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .labelReservedIconWidth(24)
                }

                NavigationLink {
                    EmailSettingsView(profile: profile)
                } label: {
                    Label("Email", systemImage: "envelope")
                        .labelReservedIconWidth(24)
                }
            }
        }
    }

    @MainActor
    private func loadStats() async {
        let trains = (try? modelContext.fetch(FetchDescriptor<Train>())) ?? []
        let stops = (try? modelContext.fetch(FetchDescriptor<Stop>())) ?? []

        let stats = await Task.detached(priority: .userInitiated) {
            let selectedStopsByTrain = Dictionary(grouping: stops.filter { $0.is_selected }, by: { $0.id })
            let totalDelay = trains.reduce(0) { total, train in
                let lastSelectedStop = selectedStopsByTrain[train.id]?
                    .max(by: { $0.ref_time < $1.ref_time })
                return total + max(0, lastSelectedStop?.arr_delay ?? 0)
            }

            var totalDistance = 0
            let completedStops = stops.filter { $0.is_completed && $0.is_selected }
            let groupedStops = Dictionary(grouping: completedStops, by: { $0.id })
            for (_, trainStops) in groupedStops {
                let sorted = trainStops.sorted(by: { $0.ref_time < $1.ref_time })
                if let first = sorted.first, let last = sorted.last, first.name != last.name {
                    totalDistance += distance_between_stations(from: first.name, to: last.name) ?? 0
                }
            }

            return (totalDelay, totalDistance)
        }.value

        formattedDelay = formatDelay(stats.0)
        formattedDistance = formatDistance(stats.1)
    }

    private func formatDelay(_ delay: Int) -> String {
        if delay >= 60 {
            let hours = delay / 60
            let mins = delay % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(delay)m"
    }

    private func formatDistance(_ distance: Int) -> String {
        if distance >= 1000 {
            let thousands = Double(distance) / 1000.0
            return String(format: "%.1fk km", thousands).replacingOccurrences(of: ".0k", with: "k")
        }
        return "\(distance) km"
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.imageData = editedImage.jpegData(compressionQuality: 0.85)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.imageData = originalImage.jpegData(compressionQuality: 0.85)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

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

struct EmailSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                TextField("Email Address", text: emailTextBinding())
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("App Password", text: emailBinding(\.appPassword))

                Menu {
                    Button {
                        setProvider(.apple)
                        openURL(EmailProvider.apple.linkDestination)
                    } label: {
                        Label("Apple", systemImage: EmailProvider.apple.icon)
                    }

                    Button {
                        setProvider(.google)
                        openURL(EmailProvider.google.linkDestination)
                    } label: {
                        Label("Google", systemImage: EmailProvider.google.icon)
                    }
                } label: {
                    Text("Generate App Password")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.blue)
            }
        }
        .navigationTitle("Email")
        .fontDesign(.rounded)
    }

    private func emailTextBinding() -> Binding<String> {
        Binding(
            get: { profile.emails.first?.email ?? "" },
            set: { newValue in
                var emails = profile.emails
                if emails.isEmpty {
                    emails = [Emails(provider: inferredProvider(from: newValue), email: "", appPassword: "")]
                }
                emails[0].email = newValue
                emails[0].provider = inferredProvider(from: newValue)
                profile.emails = emails
                try? modelContext.save()
            }
        )
    }

    private func setProvider(_ provider: EmailProvider) {
        var emails = profile.emails
        if emails.isEmpty {
            emails = [Emails(provider: provider, email: "", appPassword: "")]
        } else {
            emails[0].provider = provider
        }
        profile.emails = emails
        try? modelContext.save()
    }

    private func inferredProvider(from email: String) -> EmailProvider {
        let lower = email.lowercased()
        if lower.contains("@gmail.") || lower.contains("@googlemail.") {
            return .google
        }
        return .apple
    }

    private func emailBinding<Value>(_ keyPath: WritableKeyPath<Emails, Value>) -> Binding<Value> {
        Binding(
            get: {
                profile.emails.first?[keyPath: keyPath] ?? defaultEmailValue(for: keyPath)
            },
            set: { newValue in
                var emails = profile.emails
                if emails.isEmpty {
                    emails = [Emails(provider: .apple, email: "", appPassword: "")]
                }
                emails[0][keyPath: keyPath] = newValue
                profile.emails = emails
                try? modelContext.save()
            }
        )
    }

    private func defaultEmailValue<Value>(for keyPath: WritableKeyPath<Emails, Value>) -> Value {
        Emails(provider: .apple, email: "", appPassword: "")[keyPath: keyPath]
    }
}

#Preview("Profile View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self, configurations: config)

    let trainID = UUID()
    let train = Train(id: trainID, logo: "trenitalia", number: "9808", identifier: "9808-date", provider: "Trenitalia", last_update_time: Date(), delay: 0, direction: "Milano", issue: "")

    let stop1 = Stop(id: trainID, name: "Roma Termini", platform: "1", weather: "Sunny", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: Date().addingTimeInterval(-10000), arr_time_id: Date().addingTimeInterval(-10000), dep_time_eff: Date().addingTimeInterval(-10000), arr_time_eff: Date().addingTimeInterval(-10000), ref_time: Date())

    let stop2 = Stop(id: trainID, name: "Milano Centrale", platform: "2", weather: "Cloudy", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 10, arr_delay: 10, dep_time_id: Date().addingTimeInterval(600), arr_time_id: Date().addingTimeInterval(600), dep_time_eff: Date().addingTimeInterval(1200), arr_time_eff: Date().addingTimeInterval(1200), ref_time: Date())

    container.mainContext.insert(train)
    container.mainContext.insert(stop1)
    container.mainContext.insert(stop2)
    container.mainContext.insert(UserProfile(name: "Francesco"))

    return ContentView()
        .sheet(isPresented: .constant(true)) {
            ProfileView()
                .modelContainer(container)
        }
}

#Preview("Email Settings View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self, configurations: config)
    let profile = UserProfile(name: "Francesco", emails: [
        Emails(provider: .apple, email: "francescopara2003@icloud.com", appPassword: "pqmy-ncsd-qzbi-zxte")
    ])
    container.mainContext.insert(profile)

    return NavigationStack {
        EmailSettingsView(profile: profile)
            .modelContainer(container)
    }
}
