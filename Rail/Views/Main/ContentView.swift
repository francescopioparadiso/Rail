import SwiftUI
import SwiftData
import StoreKit

enum MainTab: Hashable {
    case past
    case today
}

struct ContentView: View {
    // MARK: - Properties

    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSection: MainTab = .today
    @State private var searchText = ""
    @State private var navigationPath: [Train] = []

    @Query(sort: \Favorite.index) private var favorites: [Favorite]
    @Query private var profiles: [UserProfile]
    @Query private var trains: [Train]
    @State private var profileSheet = false
    @State private var addTrainSheet = false
    @State private var addPassSheet = false
    @State private var openPrincipalPassQR = false
    @State private var favoriteTrainsSheet = false
    @State private var emailImportSheet = false
    @State private var fetchSheetDetent: PresentationDetent = .medium
    @State private var ticketSyncProgresses: [String: EmailTicketSyncProgress] = [:]
    @State private var isFetchingEmailTickets = false
    @State private var showFetchResultCard = false
    @State private var fetchedTicketsCount = 0
    @State private var emailFetchTask: Task<Void, Never>?
    @State private var accountProgresses: [AccountSyncProgress] = []
    @State private var hasStartedAutoFetch = false
    @State private var fetchingAccountEmails: [String] = []

    @State private var favoritePreloadStates: [UUID: PreloadState] = [:]
    @State private var preparedFavoriteTrains: [UUID: PreparedFavoriteTrain] = [:]
    @State private var favoritePreloadTask: Task<Void, Never>?
    @State private var favoriteRefreshGeneration = 0
    @State private var hasPreloadedFavorites = false

    @State private var ticketTrainID: UUID? = nil
    @State private var ticketSeatID: UUID? = nil
    @State private var showTicketView = false

    // MARK: - Computed

    private var fetchEmailsFound: Int {
        let found = ticketSyncProgresses.values.map(\.emailsFound).reduce(0, +)
        return found > 0 ? found : fetchedTicketsCount
    }

    private var showsFetchToolbarButton: Bool {
        isFetchingEmailTickets || showFetchResultCard
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            sectionMenu
        }
        .blendedToolbarItemBackground()

        // No spacer between these two: without one they share a single glass
        // container, with the profile picture at the very edge of the bar.
        if showsFetchToolbarButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openEmailFetchSheet()
                } label: {
                    emailFetchToolbarLabel
                }
                .fontDesign(appFontDesign)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            ProfileToolbarButton(profileSheet: $profileSheet)
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                addPassSheet = true
            } label: {
                Image(systemName: "ticket")
            }
        }

        ToolbarSpacer(.fixed, placement: .bottomBar)

        DefaultToolbarItem(kind: .search, placement: .bottomBar)

        ToolbarSpacer(.fixed, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                favoriteTrainsSheet = true
            } label: {
                Label("Favorites", systemImage: "heart")
            }
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                addTrainSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var sectionTitle: String {
        selectedSection == .today ? "Today" : "Past"
    }

    private var fetchProgressTitle: String {
        if ticketSyncProgresses.isEmpty {
            return String(localized: "Connecting…")
        }
        if ticketSyncProgresses.values.allSatisfy({ $0.stage == .searching }) {
            return String(localized: "Searching…")
        }
        if ticketSyncProgresses.values.allSatisfy({ $0.stage == .finished }) {
            return String(localized: "Finishing up…")
        }
        return String(localized: "Fetching \(fetchGlobalPercentage)%")
    }

    private var fetchGlobalPercentage: Int {
        let totalFound = accountProgresses.reduce(0) { $0 + $1.found }
        let totalProcessed = accountProgresses.reduce(0) { $0 + $1.processed }
        guard totalFound > 0 else { return 0 }
        return min(100, Int((Double(totalProcessed) / Double(totalFound)) * 100))
    }

    private var fetchProgressSublabel: String? {
        if ticketSyncProgresses.isEmpty {
            return String(localized: "This can take a moment on the first scan.")
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        navigationRoot
            .background(appBackgroundColor.ignoresSafeArea())
            .handlesSharedTrains { section in
                // surface the imported journey instead of leaving it buried
                withAnimation(.snappy) {
                    profileSheet = false
                    addTrainSheet = false
                    addPassSheet = false
                    favoriteTrainsSheet = false
                    emailImportSheet = false
                    navigationPath = []
                    selectedSection = section
                }
            }
            .onChange(of: selectedSection) { _, _ in
                navigationPath = []
            }
            .onAppear(perform: handleAppear)
            .task {
                await UserProfile.maintainSyncedProfile(in: modelContext)
            }
            .onChange(of: profiles.count) { _, _ in
                UserProfile.reconcile(in: modelContext, createIfNeeded: false)
            }
            .onChange(of: favoriteTrainsSheet) { _, isOpen in
                if isOpen {
                    hasPreloadedFavorites = true
                    reloadPreloadedFavorites()
                }
            }
            .onChange(of: favorites.map(\.id)) { _, _ in
                guard hasPreloadedFavorites || favoriteTrainsSheet else { return }
                reloadPreloadedFavorites()
            }
            .onDisappear {
                favoritePreloadTask?.cancel()
                emailFetchTask?.cancel()
            }
            .sheet(isPresented: $profileSheet) {
                ProfileView()
            }
            .sheet(isPresented: $addTrainSheet) {
                AddTrainView(focusInitially: true)
            }
            .sheet(isPresented: $addPassSheet) {
                PassView(openPrincipalPassQR: openPrincipalPassQR)
            }
            .onChange(of: addPassSheet) { _, isPresented in
                if !isPresented {
                    openPrincipalPassQR = false
                }
            }
            .sheet(isPresented: $favoriteTrainsSheet) {
                FavoriteTrainsView(
                    preloadStates: $favoritePreloadStates,
                    preparedTrains: $preparedFavoriteTrains,
                    onTrainAdded: { selectedSection = .today }
                )
            }
            .sheet(isPresented: $emailImportSheet) {
                emailImportSheetContent
            }
            .onOpenURL(perform: handleOpenURL)
    }

    // MARK: - Subviews

    private var navigationRoot: some View {
        NavigationStack(path: $navigationPath) {
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appBackgroundColor)
                .navigationDestination(for: Train.self) { train in
                    DetailsView(
                        train: train,
                        showTicketInitially: $showTicketView,
                        ticketSeatID: $ticketSeatID
                    )
                }
                .toolbar { mainToolbar }
                .searchable(text: $searchText, prompt: "Search")
        }
    }

    private var sectionContent: some View {
        ZStack {
            PastView(
                ticketTrainID: $ticketTrainID,
                ticketSeatID: $ticketSeatID,
                showTicketView: $showTicketView,
                searchText: $searchText,
                navigationPath: $navigationPath,
                isActive: selectedSection == .past
            )
            .opacity(selectedSection == .past ? 1 : 0)
            .allowsHitTesting(selectedSection == .past)

            TodayView(
                ticketTrainID: $ticketTrainID,
                ticketSeatID: $ticketSeatID,
                showTicketView: $showTicketView,
                searchText: $searchText,
                navigationPath: $navigationPath,
                isActive: selectedSection == .today
            )
            .opacity(selectedSection == .today ? 1 : 0)
            .allowsHitTesting(selectedSection == .today)
        }
    }

    private var emailFetchToolbarLabel: some View {
        Group {
            if isFetchingEmailTickets {
                Image(systemName: "progress.indicator")
                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous))
            } else {
                Image(systemName: "envelope")
            }
        }
        .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
        .foregroundStyle(Color.primary)
    }

    private var emailImportSheetContent: some View {
        NavigationStack {
            Group {
                if isFetchingEmailTickets {
                    EmailSyncProgressView(
                        isFetching: isFetchingEmailTickets,
                        progressTitle: fetchProgressTitle,
                        globalPercentage: Double(fetchGlobalPercentage),
                        accountProgresses: accountProgresses,
                        progressSublabel: fetchProgressSublabel
                    ) {
                        emailFetchTask?.cancel()
                        emailFetchTask = Task {
                            await fetchEmailTickets(reloadAll: true)
                        }
                    }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    EmailTrainImportView(
                        autoScanOnAppear: false,
                        onTrainAdded: { selectedSection = .today },
                        onReloadRequested: {
                            triggerEmailTicketRefresh(reloadAll: true)
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFetchingEmailTickets)
        }
        .presentationDetents(
            isFetchingEmailTickets ? [.medium] : [.large],
            selection: $fetchSheetDetent
        )
        .presentationDragIndicator(.hidden)
        .presentationBackground(appBackgroundColor)
        .onChange(of: isFetchingEmailTickets) { _, isFetching in
            fetchSheetDetent = isFetching ? .medium : .large
        }
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
            // Keep a stable max-width footprint (Today + chevron) so iOS 26's
            // menu morph doesn't clip the label when the title gets wider.
            ZStack(alignment: .leading) {
                sectionMenuLabel("Today")
                    .opacity(0)
                    .accessibilityHidden(true)

                sectionMenuLabel(sectionTitle)
            }
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private func sectionMenuLabel(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.title).fontWeight(.bold).fontDesign(appFontDesign)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions

    private func handleAppear() {
        ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
        if !hasStartedAutoFetch {
            hasStartedAutoFetch = true
            triggerEmailTicketRefresh()
        }
    }

    private func handleOpenURL(_ url: URL) {
        if url.scheme == "railapp" && url.host == "view-pass" {
            openPrincipalPassQR = true
            if !addPassSheet {
                addPassSheet = true
            }
            return
        }

        guard url.scheme == "railapp",
              url.host == "view-ticket" || url.host == "view-train",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let trainIDItem = components.queryItems?.first(where: { $0.name == "trainID" }),
              let trainIDValue = trainIDItem.value,
              let trainID = UUID(uuidString: trainIDValue) else {
            return
        }

        ticketTrainID = trainID

        if let seatIDItem = components.queryItems?.first(where: { $0.name == "seatID" }),
           let seatIDValue = seatIDItem.value {
            ticketSeatID = UUID(uuidString: seatIDValue)
        } else {
            ticketSeatID = nil
        }

        showTicketView = url.host == "view-ticket"
        selectedSection = .today
    }

    private func openEmailFetchSheet() {
        HapticFeedback.tap()
        fetchSheetDetent = isFetchingEmailTickets ? .medium : .large
        emailImportSheet = true
    }

    private func triggerEmailTicketRefresh(reloadAll: Bool = false) {
        guard !isFetchingEmailTickets else { return }
        emailFetchTask = Task {
            await fetchEmailTickets(reloadAll: reloadAll)
        }
    }

    @MainActor
    private func fetchEmailTickets(reloadAll: Bool = false) async {
        guard let profile = profiles.primary else { return }
        isFetchingEmailTickets = true
        showFetchResultCard = false
        ticketSyncProgresses = [:]
        accountProgresses = []

        let configured = profile.emails.filter(\.hasConfiguredCredentials)
        fetchingAccountEmails = configured.map(\.email)
        accountProgresses = configured.map { AccountSyncProgress(email: $0.email, found: 0, processed: 0) }
        
        let accounts = await validatedEmailAccounts(from: profile)

        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { @MainActor in
                    guard let progressIndex = accountProgresses.firstIndex(where: { $0.email == account.email }) else { return }
                    do {
                        _ = try await EmailTicketSyncService.syncAccount(
                            accountID: account.id,
                            profile: profile,
                            modelContext: modelContext,
                            reloadAll: reloadAll
                        ) { progress in
                            ticketSyncProgresses[progress.accountEmail] = progress
                            if progress.stage == .downloading || progress.stage == .fetchingDetails {
                                accountProgresses[progressIndex].found = progress.emailsFound
                                accountProgresses[progressIndex].processed = progress.emailsDownloaded
                            }
                        }
                        accountProgresses[progressIndex].processed = accountProgresses[progressIndex].found
                    } catch {
                    }
                }
            }
        }

        if !Task.isCancelled {
            fetchedTicketsCount = EmailTicketSyncService.tickets(from: profile).count
            isFetchingEmailTickets = false
            showFetchResultCard = true
        }
    }

    private func reloadPreloadedFavorites() {
        favoritePreloadTask?.cancel()
        favoritePreloadTask = Task {
            await refreshPreloadedFavorites()
        }
    }

    private func refreshPreloadedFavorites() async {
        favoriteRefreshGeneration &+= 1
        let generation = favoriteRefreshGeneration

        let currentFavorites = favorites
        await MainActor.run {
            favoritePreloadStates = Dictionary(uniqueKeysWithValues: currentFavorites.map { ($0.id, PreloadState.loading) })
            preparedFavoriteTrains = [:]
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
                    guard generation == favoriteRefreshGeneration else { return }

                    var states = favoritePreloadStates
                    var trains = preparedFavoriteTrains

                    if let prepared {
                        trains[favoriteID] = prepared
                        states[favoriteID] = .ready
                    } else {
                        trains.removeValue(forKey: favoriteID)
                        states[favoriteID] = .unavailable
                    }

                    favoritePreloadStates = states
                    preparedFavoriteTrains = trains
                }
            }
        }
    }

}

private struct ProfileToolbarButton: View {
    // MARK: - Properties

    @Query private var profiles: [UserProfile]
    @Binding var profileSheet: Bool
    @State private var profileImage: UIImage?

    // MARK: - Body

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
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
        }
        .onAppear { refreshImage() }
        .onChange(of: profiles.primary?.photo) { _, _ in refreshImage() }
        .padding(.trailing, -4).padding(.leading, -8)
    }

    // MARK: - Actions

    private func refreshImage() {
        let photoData = profiles.primary?.photo
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

@MainActor
fileprivate let previewContainer: ModelContainer = {
    let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    container.mainContext.insert(
        UserProfile(
            name: "Francesco",
            emails: [
                Emails(
                    provider: .apple,
                    email: PreviewCredentials.appleEmail,
                    appPassword: PreviewCredentials.appleAppPassword
                ),
                Emails(
                    provider: .google,
                    email: PreviewCredentials.googleEmail,
                    appPassword: PreviewCredentials.googleAppPassword
                )
            ]
        )
    )
    
    func time(_ hour: Int, _ min: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: min, second: 0, of: Date()) ?? .distantPast
    }
    
    let mockImageData = UIImage(named: "sample_code")?.pngData()
    
    let train1 = Train(id: UUID(), logo: "ITALO", number: "9904", identifier: "IT9904", provider: "italo", last_update_time: Date(), delay: -2, direction: "Milano Centrale", issue: "")
    let train2 = Train(id: UUID(), logo: "REG", number: "3224", identifier: "REG3224", provider: "trenitalia", last_update_time: Date(), delay: 5, direction: "Carmagnola", issue: "Corsa terminata a Carmagnola per un guasto sulla linea.")
    let train3 = Train(id: UUID(), logo: "REG", number: "3223", identifier: "REG3223", provider: "trenitalia", last_update_time: Date(), delay: 0, direction: "Savigliano", issue: "")
    
    [train1, train2, train3].forEach { context.insert($0) }
    
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
    
    let fav1 = Favorite(
        id: UUID(), index: 0, identifier: train1.identifier, provider: train1.provider, logo: train1.logo, number: train1.number,
        stop_names: ["Roma Termini", "Milano Centrale"], stop_ref_times: [time(6, 20), time(8, 46)]
    )
    let fav2 = Favorite(
        id: UUID(), index: 1, identifier: train2.identifier, provider: train2.provider, logo: train2.logo, number: train2.number,
        stop_names: ["Cuneo", "Carmagnola"], stop_ref_times: [time(9, 24), time(10, 9)]
    )
    [fav1, fav2].forEach { context.insert($0) }

    let passes = [
        Pass(id: UUID(), name: "Abbonamento Mensile", expiry_date: Calendar.current.date(byAdding: .day, value: 15, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Settimanale Studenti", expiry_date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Pass Regionale", expiry_date: Calendar.current.date(byAdding: .month, value: 3, to: Date())!, is_principal: true, image: mockImageData)
    ]
    passes.forEach { context.insert($0) }

    return container
}()

#Preview("Content View") {
    ContentView()
        .modelContainer(previewContainer)
}
