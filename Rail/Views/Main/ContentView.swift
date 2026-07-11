import SwiftUI
import SwiftData
import StoreKit

let app_font_design: Font.Design = .rounded
let app_background_color = Color(.secondarySystemBackground)

extension ToolbarContent {
    @ToolbarContentBuilder
    func blendedToolbarItemBackground() -> some ToolbarContent {
        sharedBackgroundVisibility(.hidden)
    }
}

// MARK: - Enums

enum current_tab: Hashable {
    case past
    case today
}

struct ContentView: View {
    // MARK: - Properties
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSection: current_tab = .today
    @State private var searchText = ""
    @State private var navigationPath: [Train] = []

    @Query(sort: \Favorite.index) private var favorites: [Favorite]
    @Query private var profiles: [UserProfile]
    // sheet variables
    @State private var profile_sheet = false
    @State private var add_train_sheet = false
    @State private var add_pass_sheet = false
    @State private var favorite_trains_sheet = false
    @State private var email_import_sheet = false

    @State private var favorite_preload_states: [UUID: PreloadState] = [:]
    @State private var prepared_favorite_trains: [UUID: PreparedFavoriteTrain] = [:]
    @State private var favorite_preload_task: Task<Void, Never>?
    @State private var favorite_refresh_generation = 0
    @State private var has_preloaded_favorites = false
    
    // deep link variables
    @State private var ticketTrainID: UUID? = nil
    @State private var ticketSeatID: UUID? = nil
    @State private var show_ticket_view = false
    
    // MARK: - Body
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if selectedSection == .today {
                    TodayView(
                        ticketTrainID: $ticketTrainID,
                        ticketSeatID: $ticketSeatID,
                        show_ticket_view: $show_ticket_view,
                        searchText: $searchText,
                        navigationPath: $navigationPath,
                        isActive: true
                    )
                } else {
                    PastView(
                        ticketTrainID: $ticketTrainID,
                        ticketSeatID: $ticketSeatID,
                        show_ticket_view: $show_ticket_view,
                        searchText: $searchText,
                        navigationPath: $navigationPath
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app_background_color)
            .navigationDestination(for: Train.self) { train in
                DetailsView(
                    train: train,
                    show_ticket_initially: $show_ticket_view,
                    ticketSeatID: $ticketSeatID
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sectionMenu
                }
                .blendedToolbarItemBackground()

                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(profileSheet: $profile_sheet)
                }
                .blendedToolbarItemBackground()

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        HapticFeedback.confirm()
                        add_pass_sheet = true
                    } label: {
                        Image(systemName: "ticket")
                    }
                }

                ToolbarSpacer(.fixed, placement: .bottomBar)

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            HapticFeedback.confirm()
                            add_train_sheet = true
                        } label: {
                            Label("Manual entry", systemImage: "keyboard")
                        }

                        Button {
                            HapticFeedback.confirm()
                            email_import_sheet = true
                        } label: {
                            Label("From email", systemImage: "envelope")
                        }

                        Button {
                            HapticFeedback.confirm()
                            favorite_trains_sheet = true
                        } label: {
                            Label("Favorites", systemImage: "heart.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search trains")
        }
        .background(app_background_color.ignoresSafeArea())
        .onChange(of: selectedSection) { _, _ in
            navigationPath = []
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            ensureDefaultProfile()
        }
        .onChange(of: favorite_trains_sheet) { _, isOpen in
            if isOpen {
                has_preloaded_favorites = true
                reload_preloaded_favorites()
            }
        }
        .onChange(of: favorites.map(\.id)) { _, _ in
            guard has_preloaded_favorites || favorite_trains_sheet else { return }
            reload_preloaded_favorites()
        }
        .onDisappear {
            favorite_preload_task?.cancel()
        }
        .sheet(isPresented: $profile_sheet) {
            ProfileView()
        }
        .sheet(isPresented: $add_train_sheet) {
            AddTrainView(focus_initially: true)
        }
        .sheet(isPresented: $add_pass_sheet) {
            PassView()
        }
        .sheet(isPresented: $favorite_trains_sheet) {
            FavoriteTrainsView(
                preloadStates: $favorite_preload_states,
                preparedTrains: $prepared_favorite_trains,
                onTrainAdded: { selectedSection = .today }
            )
        }
        .sheet(isPresented: $email_import_sheet) {
            EmailTrainImportView(
                onTrainAdded: { selectedSection = .today }
            )
        }
        .onOpenURL { url in
            if url.scheme == "railapp" && url.host == "view-pass" {
                if !add_pass_sheet {
                    add_pass_sheet = true
                }
            } else if url.scheme == "railapp" && (url.host == "view-ticket" || url.host == "view-train") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if let trainIDItem = components.queryItems?.first(where: { $0.name == "trainID" }),
                       let trainIDValue = trainIDItem.value,
                       let trainID = UUID(uuidString: trainIDValue) {
                        
                        self.ticketTrainID = trainID
                        
                        if let seatIDItem = components.queryItems?.first(where: { $0.name == "seatID" }),
                           let seatIDValue = seatIDItem.value {
                            self.ticketSeatID = UUID(uuidString: seatIDValue)
                        } else {
                            self.ticketSeatID = nil
                        }
                        
                        self.show_ticket_view = url.host == "view-ticket"
                        self.selectedSection = .today
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties
    private var sectionTitle: String {
        selectedSection == .today ? "Today" : "Past"
    }

    private var sectionMenu: some View {
        Menu {
            Button {
                HapticFeedback.select()
                selectedSection = .today
            } label: {
                Label {
                    Text("Today")
                } icon: {
                    if selectedSection == .today {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "calendar.day.timeline.leading")
                    }
                }
            }

            Button {
                HapticFeedback.select()
                selectedSection = .past
            } label: {
                Label {
                    Text("Past")
                } icon: {
                    if selectedSection == .past {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Text(sectionTitle)
                    .font(.largeTitle).fontWeight(.bold).fontDesign(app_font_design)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .padding(.leading, -8)
    }

    // MARK: - Functions
    private func reload_preloaded_favorites() {
        favorite_preload_task?.cancel()
        favorite_preload_task = Task {
            await refresh_preloaded_favorites()
        }
    }

    private func ensureDefaultProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }

    private func refresh_preloaded_favorites() async {
        favorite_refresh_generation &+= 1
        let generation = favorite_refresh_generation

        let currentFavorites = favorites
        await MainActor.run {
            favorite_preload_states = Dictionary(uniqueKeysWithValues: currentFavorites.map { ($0.id, PreloadState.loading) })
            prepared_favorite_trains = [:]
        }

        await withTaskGroup(of: (UUID, PreparedFavoriteTrain?).self) { group in
            for favorite in currentFavorites {
                let favoriteID = favorite.id
                group.addTask {
                    let prepared = await FavoriteTrainService.loadTodayTrain(for: favorite)
                    return (favoriteID, prepared)
                }
            }

            for await (favoriteID, prepared) in group {
                await MainActor.run {
                    guard generation == favorite_refresh_generation else { return }

                    var states = favorite_preload_states
                    var trains = prepared_favorite_trains

                    if let prepared {
                        trains[favoriteID] = prepared
                        states[favoriteID] = .ready
                    } else {
                        trains.removeValue(forKey: favoriteID)
                        states[favoriteID] = .unavailable
                    }

                    favorite_preload_states = states
                    prepared_favorite_trains = trains
                }
            }
        }
    }

}

private struct ProfileToolbarButton: View {
    @Query private var profiles: [UserProfile]
    @Binding var profileSheet: Bool
    @State private var profileImage: UIImage?

    var body: some View {
        Button {
            HapticFeedback.confirm()
            profileSheet = true
        } label: {
            Group {
                if let profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { refreshImage() }
        .onChange(of: profiles.first?.photo) { _, _ in refreshImage() }
    }

    private func refreshImage() {
        let photoData = profiles.first?.photo
        Task {
            let image = await Task.detached(priority: .utility) {
                photoData.flatMap { UIImage(data: $0) }
            }.value
            await MainActor.run {
                profileImage = image
            }
        }
    }
}

// MARK: - Previews

private struct ContentViewEmailImportPreview: View {
    let container: ModelContainer

    var body: some View {
        ContentView()
            .modelContainer(container)
            .sheet(isPresented: .constant(true)) {
                EmailTrainImportView(onTrainAdded: {})
                    .modelContainer(container)
            }
    }
}

#Preview("Content View") {
    // MARK: - SwiftData Setup
    let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    func time(_ hour: Int, _ min: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: min, second: 0, of: Date()) ?? .distantPast
    }
    
    let mockImageData = UIImage(named: "sample_code")?.pngData()
    
    // MARK: - Trains & Stops Data
    let train1 = Train(id: UUID(), logo: "ITALO", number: "9904", identifier: "IT9904", provider: "italo", last_update_time: Date(), delay: -2, direction: "Milano Centrale", issue: "")
    let train2 = Train(id: UUID(), logo: "REG", number: "3224", identifier: "REG3224", provider: "trenitalia", last_update_time: Date(), delay: 5, direction: "Carmagnola", issue: "Corsa terminata a Carmagnola per un guasto sulla linea.")
    let train3 = Train(id: UUID(), logo: "REG", number: "3223", identifier: "REG3223", provider: "trenitalia", last_update_time: Date(), delay: 0, direction: "Savigliano", issue: "")
    
    [train1, train2, train3].forEach { context.insert($0) }
    
    // Train 2 Journey Details (with delays and status variations)
    let stopData2: [(String, Int, Int, String, Int, Int, Int, String)] = [
        ("Cuneo", 9, 24, "☀️ 10°C", 0, 0, 0, "3"),
        ("Centallo", 9, 34, "☀️ 10°C", 0, -2, -1, "1"),
        ("Fossano", 9, 43, "🌤️ 11°C", 0, 0, 0, "4"),
        ("Savigliano", 9, 51, "🌤️ 11°C", 2, 0, 0, "2"),
        ("Cavallermaggiore", 9, 57, "🌥️ 12°C", 0, 3, 4, "1"),
        ("Carmagnola", 10, 9, "🌥️ 12°C", 0, 5, 0, "3"),
        ("Torino Lingotto", 10, 28, "☁️ 9°C", 3, 0, 0, "--"),
        ("Torino Porta Nuova", 10, 35, "☁️ 9°C", 3, 0, 0, "--")
    ]
    
    let selectedStations = ["Savigliano", "Cavallermaggiore", "Carmagnola", "Torino Lingotto", "Torino Porta Nuova"]
    
    for (name, h, m, weatherStr, statusValue, aDelay, dDelay, plat) in stopData2 {
        let isLastValid = name == "Carmagnola"
        let isFirst = name == "Cuneo"
        let scheduledArr = time(h, m)
        let scheduledDep = time(h, m + 1)
        
        context.insert(Stop(
            id: train2.id, name: name, platform: plat, weather: weatherStr,
            is_selected: selectedStations.contains(name), status: statusValue,
            is_completed: name != "Torino Lingotto" && name != "Torino Porta Nuova",
            is_in_station: isLastValid, dep_delay: dDelay, arr_delay: aDelay,
            dep_time_id: isLastValid ? .distantPast : scheduledDep,
            arr_time_id: isFirst ? .distantPast : scheduledArr,
            dep_time_eff: isLastValid ? .distantPast : scheduledDep.addingTimeInterval(TimeInterval(dDelay * 60)),
            arr_time_eff: isFirst ? .distantPast : scheduledArr.addingTimeInterval(TimeInterval(aDelay * 60)),
            ref_time: scheduledArr
        ))
    }
    
    context.insert(Stop(id: train1.id, name: "Roma Termini", platform: "24", weather: "☀️ 14°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: time(6, 20), arr_time_id: .distantPast, dep_time_eff: time(6, 20), arr_time_eff: .distantPast, ref_time: time(6, 20)))
    context.insert(Stop(id: train1.id, name: "Milano Centrale", platform: "5", weather: "🌫️ 6°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 0, arr_delay: -2, dep_time_id: .distantPast, arr_time_id: time(8, 46), dep_time_eff: .distantPast, arr_time_eff: time(8, 44), ref_time: time(8, 46)))
    context.insert(Stop(id: train3.id, name: "Torino Porta Nuova", platform: "15", weather: "☁️ 9°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: time(12, 50), arr_time_id: .distantPast, dep_time_eff: time(12, 50), arr_time_eff: .distantPast, ref_time: time(12, 50)))
    context.insert(Stop(id: train3.id, name: "Savigliano", platform: "1AF", weather: "🌧️ 7°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 0, arr_delay: 5, dep_time_id: .distantPast, arr_time_id: time(14, 22), dep_time_eff: .distantPast, arr_time_eff: time(14, 27), ref_time: time(14, 22)))

    // MARK: - Seats Data
    let seats = [
        Seat(id: UUID(), trainID: train2.id, name: "Pierpaolo", carriage: "1", number: "2D", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Davide", carriage: "1", number: "7B", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Andrea", carriage: "2", number: "8C", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Marco", carriage: "4", number: "10C", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Luca", carriage: "8", number: "10D", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Riccardo", carriage: "11", number: "11A", image: mockImageData),
        Seat(id: UUID(), trainID: train2.id, name: "Fabio", carriage: "12", number: "14B", image: mockImageData)
    ]
    seats.forEach { context.insert($0) }
    
    // MARK: - Favorites Data
    let fav1 = Favorite(
        id: UUID(), index: 0, identifier: train1.identifier, provider: train1.provider, logo: train1.logo, number: train1.number,
        stop_names: ["Roma Termini", "Milano Centrale"], stop_ref_times: [time(6, 20), time(8, 46)]
    )
    let fav2 = Favorite(
        id: UUID(), index: 1, identifier: train2.identifier, provider: train2.provider, logo: train2.logo, number: train2.number,
        stop_names: ["Cuneo", "Carmagnola"], stop_ref_times: [time(9, 24), time(10, 9)]
    )
    [fav1, fav2].forEach { context.insert($0) }

    // MARK: - Passes Data
    let passes = [
        Pass(id: UUID(), name: "Abbonamento Mensile", expiry_date: Calendar.current.date(byAdding: .day, value: 15, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Settimanale Studenti", expiry_date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Pass Regionale", expiry_date: Calendar.current.date(byAdding: .month, value: 3, to: Date())!, is_principal: true, image: mockImageData)
    ]
    passes.forEach { context.insert($0) }

    return ContentView()
        .modelContainer(container)
}

#Preview("Email Import") {
    let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    func departure(daysFromNow: Int, hour: Int, minute: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    let ticketReady = EmailContent(
        imapUID: "1001",
        date: Date(),
        link: CheckInLink.url(for: "abc123def456ghi789jkl012"),
        departureDate: departure(daysFromNow: 3, hour: 9, minute: 15),
        trainNumber: "9808",
        departureStation: "Roma Termini",
        arrivalStation: "Milano Centrale"
    )
    let ticketLoading = EmailContent(
        imapUID: "1002",
        date: Date(),
        link: CheckInLink.url(for: "mno345pqr678stu901vwx234"),
        departureDate: departure(daysFromNow: 5, hour: 14, minute: 30),
        trainNumber: "9904",
        departureStation: "Torino Porta Nuova",
        arrivalStation: "Roma Termini"
    )
    let ticketUnavailable = EmailContent(
        imapUID: "1003",
        date: Date(),
        link: CheckInLink.url(for: "yza567bcd890efg123hij456"),
        departureDate: departure(daysFromNow: 7, hour: 18, minute: 45),
        trainNumber: "3224",
        departureStation: "Cuneo",
        arrivalStation: "Torino Porta Nuova"
    )

    container.mainContext.insert(
        UserProfile(
            name: "Francesco",
            emails: [
                Emails(
                    provider: .apple,
                    email: "user@icloud.com",
                    appPassword: "preview-password",
                    content: [ticketReady, ticketLoading, ticketUnavailable]
                )
            ]
        )
    )

    return ContentViewEmailImportPreview(container: container)
}
