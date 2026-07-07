import SwiftUI
import SwiftData
import Charts
import PhotosUI
import EventKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = UserProfile.shared
    @Query private var stops: [Stop]
    @State private var showImagePicker = false
    
    @Query private var trains: [Train]
    @Query private var seats: [Seat]
    
    


    // Compute total delay from the final selected stop of each trip.
    private var totalDelay: Int {
        let selectedStopsByTrain = Dictionary(grouping: stops.filter { $0.is_selected }, by: { $0.id })
        
        return trains.reduce(0) { total, train in
            let lastSelectedStop = selectedStopsByTrain[train.id]?
                .max(by: { $0.ref_time < $1.ref_time })
            
            return total + max(0, lastSelectedStop?.arr_delay ?? 0)
        }
    }
    
    // Compute total distance based on completed journeys
    private var totalDistance: Int {
        var total = 0
        let completedStops = stops.filter { $0.is_completed && $0.is_selected }
        let groupedStops = Dictionary(grouping: completedStops, by: { $0.id })
        for (_, trainStops) in groupedStops {
            let sorted = trainStops.sorted(by: { $0.ref_time < $1.ref_time })
            if let first = sorted.first, let last = sorted.last, first.name != last.name {
                total += distance_between_stations(from: first.name, to: last.name) ?? 0
            }
        }
        return total
    }
    
    private var formattedDelay: String {
        let delay = totalDelay
        if delay >= 60 {
            let hours = delay / 60
            let mins = delay % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        } else {
            return "\(delay)m"
        }
    }
    
    private var formattedDistance: String {
        let distance = totalDistance
        if distance >= 1000 {
            let thousands = Double(distance) / 1000.0
            return String(format: "%.1fk km", thousands).replacingOccurrences(of: ".0k", with: "k")
        } else {
            return "\(distance) km"
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 24) {
                        // 1. Image + Name
                        VStack(spacing: 16) {
                            Button {
                                showImagePicker = true
                            } label: {
                                if let data = profile.imageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 200, height: 200)
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
                                ImagePicker(imageData: Binding(get: { profile.imageData }, set: { profile.imageData = $0 }))
                            }
                            
                            TextField("Name", text: Binding(
                                get: { "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces) },
                                set: { newValue in
                                    let components = newValue.split(separator: " ", maxSplits: 1).map(String.init)
                                    profile.firstName = components.first ?? ""
                                    profile.lastName = components.count > 1 ? components.last! : ""
                                }
                            ))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                
                        // 2. Metric Cards
                        HStack(spacing: 16) {
                            // Delay Card
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

                            // Distance Card
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
                
                // 3. Settings Form
                Section(header: Text("Settings")) {
                    NavigationLink(destination: CalendarSettingsView()) {
                        Label("Calendar", systemImage: "calendar")
                            .labelReservedIconWidth(24)
                    }
                    
                    NavigationLink(destination: EmailSettingsView()) {
                        Label("Email", systemImage: "envelope")
                            .labelReservedIconWidth(24)
                    }
                }
            }
            .fontDesign(.rounded)
            .background(Color(UIColor.systemGroupedBackground))
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

        .onDisappear {
            profile.saveAll()
        }
    }


}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, configurations: config)
        
        let trainID = UUID()
        let train = Train(id: trainID, logo: "trenitalia", number: "9808", identifier: "9808-date", provider: "Trenitalia", last_update_time: Date(), delay: 0, direction: "Milano", issue: "")
        
        let stop1 = Stop(id: trainID, name: "Roma Termini", platform: "1", weather: "Sunny", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: Date().addingTimeInterval(-10000), arr_time_id: Date().addingTimeInterval(-10000), dep_time_eff: Date().addingTimeInterval(-10000), arr_time_eff: Date().addingTimeInterval(-10000), ref_time: Date())
        
        let stop2 = Stop(id: trainID, name: "Milano Centrale", platform: "2", weather: "Cloudy", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 10, arr_delay: 10, dep_time_id: Date().addingTimeInterval(600), arr_time_id: Date().addingTimeInterval(600), dep_time_eff: Date().addingTimeInterval(1200), arr_time_eff: Date().addingTimeInterval(1200), ref_time: Date())
        
        container.mainContext.insert(train)
        container.mainContext.insert(stop1)
        container.mainContext.insert(stop2)
        
        return ContentView()
            .sheet(isPresented: .constant(true)) {
                ProfileView()
                    .modelContainer(container)
            }
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
                parent.imageData = UserProfile.preparedProfileImageData(from: editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.imageData = UserProfile.preparedProfileImageData(from: originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct CalendarSettingsView: View {
    @ObservedObject var profile = UserProfile.shared
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    
    @State private var availableCalendars: [EKCalendar] = []
    @State private var isAuthorized: Bool = CalendarManager.shared.isAuthorized
    @State private var showPermissionAlert: Bool = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Add to calendar automatically", isOn: Binding(
                    get: { profile.autoSyncToCalendar },
                    set: { newValue in
                        profile.autoSyncToCalendar = newValue
                        if newValue { resyncAll() } else { removeAll() }
                    }
                ))
                
                Picker("Calendar", selection: Binding(
                    get: { profile.selectedCalendarIdentifier },
                    set: { newValue in
                        profile.selectedCalendarIdentifier = newValue
                        resyncAll()
                    }
                )) {
                    Text("Default").tag("")
                    ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal.calendarIdentifier)
                    }
                }
                
                Picker("Title Format", selection: Binding(
                    get: { profile.calendarTitleFormat },
                    set: { newValue in
                        profile.calendarTitleFormat = newValue
                        resyncAll()
                    }
                )) {
                    Text("Train").tag("Train")
                    Text("Train 9808").tag("Train {number}")
                    Text("🚄 Train").tag("🚄 Train")
                    Text("🚂 Train").tag("🚂 Train")
                    Text("🚉 Train").tag("🚉 Train")
                    Text("Train 1/15A").tag("Train {carriage}/{number}")
                }
                
                Picker("Travel time", selection: Binding(
                    get: { profile.calendarTravelTime },
                    set: { newValue in
                        profile.calendarTravelTime = newValue
                        resyncAll()
                    }
                )) {
                    Text("None").tag(Double(0))
                    Text("15 minutes").tag(Double(900))
                    Text("30 minutes").tag(Double(1800))
                    Text("45 minutes").tag(Double(2700))
                    Text("1 hour").tag(Double(3600))
                    Text("2 hours").tag(Double(7200))
                }
            }
            .disabled(!isAuthorized)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
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
    
    private func resyncAll() {
        guard isAuthorized && profile.autoSyncToCalendar else { return }
        Task {
            for train in trains {
                let trainStops = stops.filter { $0.id == train.id }
                let trainSeats = seats.filter { $0.trainID == train.id }
                await CalendarManager.shared.syncTrainEvent(
                    train: train,
                    stops: trainStops,
                    seats: trainSeats,
                    titleFormat: profile.calendarTitleFormat,
                    calendarIdentifier: profile.selectedCalendarIdentifier,
                    travelTime: profile.calendarTravelTime
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
    @ObservedObject var profile = UserProfile.shared
    
    @State private var showingLinkSheet = false
    @State private var selectedProvider: String?
    @State private var newEmail = ""
    @State private var newPassword = ""

    var body: some View {
        List {
            Section {
                if profile.linkedEmails.isEmpty {
                    Text("No emails linked yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(profile.linkedEmails) { linkedEmail in
                        NavigationLink(destination: EmailInboxView(linkedEmail: linkedEmail)) {
                            HStack(spacing: 16) {
                                Image(systemName: linkedEmail.provider == "Google" ? "envelope.fill" : "icloud.fill")
                                    .foregroundColor(linkedEmail.provider == "Google" ? .red : .blue)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(linkedEmail.email)
                                        .font(.headline)
                                    Text(linkedEmail.provider)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        profile.linkedEmails.remove(atOffsets: indexSet)
                    }
                }
            } header: {
                Text("\(profile.linkedEmails.count) emails")
            }
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        selectedProvider = "Google"
                        showingLinkSheet = true
                    } label: {
                        Label("Google Mail", systemImage: "envelope")
                    }
                    Button {
                        selectedProvider = "iCloud"
                        showingLinkSheet = true
                    } label: {
                        Label("iCloud Mail", systemImage: "icloud")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLinkSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Account Details"), footer: Text(selectedProvider == "Google" ? "Enter your Google email and an App Password. Note that 2-Step Verification must be enabled on your Google account." : "Enter your iCloud email and an App-Specific Password.")) {
                        TextField("Email Address", text: $newEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        SecureField("App Password", text: $newPassword)
                    }
                    
                    Section {
                        if selectedProvider == "Google" {
                            Link("Generate App Password", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                                .foregroundColor(.blue)
                        } else if selectedProvider == "iCloud" {
                            Link("Generate App-Specific Password", destination: URL(string: "https://appleid.apple.com/account/manage")!)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .navigationTitle("Link \(selectedProvider ?? "")")
                .navigationBarTitleDisplayMode(.inline)
                .fontDesign(.rounded)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingLinkSheet = false
                            newEmail = ""
                            newPassword = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let provider = selectedProvider, !newEmail.isEmpty, !newPassword.isEmpty {
                                let newLinked = LinkedEmail(provider: provider, email: newEmail, appPassword: newPassword)
                                profile.linkedEmails.append(newLinked)
                            }
                            showingLinkSheet = false
                            newEmail = ""
                            newPassword = ""
                        }
                        .disabled(newEmail.isEmpty || newPassword.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
