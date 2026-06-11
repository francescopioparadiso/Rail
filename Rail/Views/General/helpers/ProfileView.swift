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
    
    
    @State private var availableCalendars: [EKCalendar] = []
    @State private var isAuthorized: Bool = CalendarManager.shared.isAuthorized
    @State private var showPermissionAlert: Bool = false
    
    private var selectedCalendarTitle: String {
        if profile.selectedCalendarIdentifier.isEmpty {
            return "Default"
        }
        return availableCalendars.first(where: { $0.calendarIdentifier == profile.selectedCalendarIdentifier })?.title ?? "Default"
    }
    
    private var travelTimeTitle: String {
        if profile.calendarTravelTime == 0 { return NSLocalizedString("None", comment: "") }
        let minutes = Int(profile.calendarTravelTime / 60)
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

    // Compute total delay based on completed stops with delays
    private var totalDelay: Int {
        stops.filter { $0.is_completed && $0.is_selected }.reduce(0) { $0 + max(0, $1.arr_delay) }
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
                    VStack(spacing: 20) {
                        // 1. Image + Name
                        VStack(spacing: 16) {
                    Button {
                        showImagePicker = true
                    } label: {
                        if let data = profile.imageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
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
                                        .frame(width: 40, height: 40)
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
                .padding(.top, 20)
                
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
                .padding(.horizontal)
                .padding(.bottom, 10)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                
                // 3. Calendar Sync Form
                Section(header: Text("Calendar Sync")) {
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
                // No height constraints! It natively scrolls.
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
            Button("Cancel", role: .cancel) { dismiss() }
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
                parent.imageData = editedImage.jpegData(compressionQuality: 0.8)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.imageData = originalImage.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
