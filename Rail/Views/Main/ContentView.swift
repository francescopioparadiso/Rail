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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSection: MainTab = .today
    @State private var deepLinks = DeepLinkRouter.shared
    @State private var pendingRouteTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var navigationPath: [Train] = []

    @Query(sort: \Favorite.index) private var favorites: [Favorite]
    @Query private var profiles: [UserProfile]
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    @State private var profileSheet = false
    /// Set by the mail sheet's shortcut: Profile opens already on Email settings.
    @State private var profileOpensEmail = false
    @State private var addTrainSheet = false
    @State private var addPassSheet = false
    @State private var openPrincipalPassQR = false
    @State private var favoriteTrainsSheet = false
    @State private var emailImportSheet = false
    @State private var stationBoardSheet = false
    @State private var fetchSheetDetent: PresentationDetent = .medium
    @State private var ticketSyncProgresses: [String: EmailTicketSyncProgress] = [:]
    @State private var isFetchingEmailTickets = false
    /// Whether the running fetch gets the full progress view: it reads the whole
    /// mailbox (the first scan, or a start-over), or there is no list yet to keep on
    /// screen. Looking for what has arrived since, above a list, keeps the list.
    @State private var isFullEmailScan = false
    @State private var showFetchResultCard = false

    /// Set only by previews and screenshot builds: it puts the mail button on the
    /// toolbar in its finished state and keeps the auto-sync away from the network,
    /// so a made-up mailbox stays made up. The app itself never passes it.
    private let usesMockMailbox: Bool

    /// Passed with `usesMockMailbox` so a screenshot can be taken at any hour and
    /// still show the journeys where the mock data puts them.
    private let previewNow: Date?

    init(usesMockMailbox: Bool = false, previewNow: Date? = nil) {
        self.usesMockMailbox = usesMockMailbox
        self.previewNow = previewNow
        _showFetchResultCard = State(initialValue: usesMockMailbox)
    }
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
    @State private var scrollToNextStation = false
    /// The Duo reserves a strip down the right bezel, folded or opened out, and the
    /// system moves the toolbar's buttons into it, one above the other. Other
    /// iPhones have no such inset, so the toolbar keeps its top and bottom bars.
    @State private var hasBezelStrip = false
    private let cloudSync = CloudSyncMonitor.shared

    // MARK: - Computed

    private var fetchEmailsFound: Int {
        let found = ticketSyncProgresses.values.map(\.emailsFound).reduce(0, +)
        return found > 0 ? found : fetchedTicketsCount
    }

    private var showsFullEmailScan: Bool {
        isFetchingEmailTickets && isFullEmailScan
    }

    private var showsFetchToolbarButton: Bool {
        isFetchingEmailTickets || showFetchResultCard
    }

    @ToolbarContentBuilder
    private var boardToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HapticFeedback.tap()
                stationBoardSheet = true
            } label: {
                Image(systemName: "tablecells")
            }
            .fontDesign(appFontDesign)
        }
    }

    @ToolbarContentBuilder
    private var mailToolbarItem: some ToolbarContent {
        if showsFetchToolbarButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openEmailFetchSheet()
                } label: {
                    // One plain symbol: a label built from several views is not
                    // taken into the strip's capsule and is left out on its own.
                    mailSymbol
                }
                .fontDesign(appFontDesign)
            }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ProfileToolbarButton(profileSheet: $profileSheet, trailingInset: 0)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            sectionMenu
        }
        .blendedToolbarItemBackground()
        
        if hasBezelStrip {
            // In the strip the buttons stack in the order they are declared. No negative
            // padding, which would push an icon off the middle of its button.
            if horizontalSizeClass == .regular {
                // Opened out: timetables on their own, one spacer, then mail and profile.
                boardToolbarItem

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                mailToolbarItem

                profileToolbarItem
            } else {
                // Folded: profile and mail together, one spacer, then timetables.
                profileToolbarItem

                mailToolbarItem

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                boardToolbarItem
            }

            if horizontalSizeClass == .regular {
                // Opened out, the bottom bar runs along the list's column as on any
                // iPhone: pass, search, then favorites and add.
                passToolbarItem

                ToolbarSpacer(.fixed, placement: .bottomBar)

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.fixed, placement: .bottomBar)

                favoritesToolbarItem(tightened: true)
                addToolbarItem
            } else {
                // The system shrinks the search field to a magnifier in the strip. It
                // sits above the pass button, with the one spacer of the strip between.
                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.fixed, placement: .bottomBar)

                passToolbarItem
                favoritesToolbarItem(tightened: false)
                addToolbarItem
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticFeedback.tap()
                    stationBoardSheet = true
                } label: {
                    Image(systemName: "tablecells")
                }
                .fontDesign(appFontDesign)
            }

            if showsFetchToolbarButton {
                // inside the condition: with no mail button to separate, the spacer
                // would only strand the board button away from the profile
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openEmailFetchSheet()
                    } label: {
                        emailFetchToolbarLabel
                    }
                    .fontDesign(appFontDesign)
                    .padding(.trailing, -8)
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
        }

        if !hasBezelStrip {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }

        if !hasBezelStrip {
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    HapticFeedback.confirm()
                    favoriteTrainsSheet = true
                } label: {
                    Label("Favorites", systemImage: "heart")
                }
                .padding(.trailing, -8)
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
    }

    @ToolbarContentBuilder
    private var passToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                addPassSheet = true
            } label: {
                Image(systemName: "ticket")
            }
        }
    }

    @ToolbarContentBuilder
    private func favoritesToolbarItem(tightened: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                favoriteTrainsSheet = true
            } label: {
                Label("Favorites", systemImage: "heart")
            }
            .padding(.trailing, tightened ? -8 : 0)
        }
    }

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                HapticFeedback.confirm()
                addTrainSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    /// A key, not a String: `Text(String)` is the verbatim overload, so the title
    /// stayed English while the menu beside it translated.
    private var sectionTitle: LocalizedStringKey {
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
                    stationBoardSheet = false
                    navigationPath = []
                    selectedSection = section
                }
            }
            .onChange(of: selectedSection) { _, _ in
                navigationPath = []
            }
            .onAppear(perform: handleAppear)
            .alert(
                "Fetching iCloud Data",
                isPresented: Binding(
                    get: { cloudSync.showsFetchAlert },
                    set: { if !$0 { cloudSync.dismissAlert() } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your trains and passes are being downloaded from iCloud. They will appear in a moment.")
            }
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
            .sheet(isPresented: $profileSheet, onDismiss: { profileOpensEmail = false }) {
                ProfileView(opensEmail: profileOpensEmail)
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
            .sheet(isPresented: $stationBoardSheet) {
                StationBoardView()
            }
            .onOpenURL(perform: handleOpenURL)
            .onChange(of: deepLinks.pending) { _, _ in consumePendingDeepLink() }
    }

    // MARK: - Subviews

    /// A wide window, like the iPhone Duo opened out or an iPad, gets the list on the
    /// left and the journey on the right; a narrow one pushes the journey over the list.
    @ViewBuilder
    private var navigationRoot: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitRoot
            } else {
                stackRoot
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.safeAreaInsets.trailing > 40
        } action: { hasStrip in
            hasBezelStrip = hasStrip && UIDevice.current.userInterfaceIdiom == .phone
        }
    }

    private var stackRoot: some View {
        NavigationStack(path: $navigationPath) {
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appBackgroundColor)
                .navigationDestination(for: Train.self) { train in
                    journeyDetails(train)
                }
                .toolbar { mainToolbar }
                .searchable(text: $searchText, prompt: "Search")
        }
    }

    /// Deeper than the journey's background, so the list reads as its own column.
    private static let sidebarBackground = Color(.systemGray5)

    private var splitRoot: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.sidebarBackground)
                .environment(\.sidebarBackground, Self.sidebarBackground)
                // A row opens its journey in the right-hand column, not on top of the list.
                .environment(\.selectTrain) { train in navigationPath = [train] }
                // The list is always there, so there is nothing to show or hide.
                .toolbar(removing: .sidebarToggle)
                .toolbar { mainToolbar }
                .searchable(text: $searchText, prompt: "Search")
                .navigationSplitViewColumnWidth(min: 380, ideal: 420, max: 480)
        } detail: {
            NavigationStack {
                if let train = navigationPath.last {
                    journeyDetails(train)
                        .id(train.id)
                } else {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(appBackgroundColor)
                }
            }
        }
    }

    private func journeyDetails(_ train: Train) -> some View {
        DetailsView(
            train: train,
            showTicketInitially: $showTicketView,
            ticketSeatID: $ticketSeatID,
            scrollToNextStation: $scrollToNextStation
        )
        .environment(\.hasBezelStrip, hasBezelStrip)
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
                isActive: selectedSection == .today,
                previewNow: previewNow
            )
            .opacity(selectedSection == .today ? 1 : 0)
            .allowsHitTesting(selectedSection == .today)
        }
    }

    /// Two different views, not one symbol swapped: the rotation would carry over to
    /// the envelope. Only the progress indicator turns.
    @ViewBuilder
    private var mailSymbol: some View {
        if showsFullEmailScan {
            Image(systemName: "progress.indicator")
                .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: true)
        } else {
            Image(systemName: "envelope")
        }
    }

    private var emailFetchToolbarLabel: some View {
        EmailFetchIcon(isFetching: showsFullEmailScan)
    }

    private var emailImportSheetContent: some View {
        NavigationStack {
            Group {
                if showsFullEmailScan {
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
                        isFetchingNewest: isFetchingEmailTickets,
                        onTrainAdded: { selectedSection = .today },
                        onReloadRequested: {
                            triggerEmailTicketRefresh(reloadAll: true)
                        },
                        onOpenEmailSettings: openEmailSettings
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showsFullEmailScan)
        }
        .presentationDetents(
            showsFullEmailScan ? [.medium] : [.large],
            selection: $fetchSheetDetent
        )
        .presentationDragIndicator(.hidden)
        .presentationBackground(appBackgroundColor)
        .onChange(of: showsFullEmailScan) { _, isFullScan in
            fetchSheetDetent = isFullScan ? .medium : .large
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

    private func sectionMenuLabel(_ title: LocalizedStringKey) -> some View {
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
        // A tap that launched the app parks its link before this view exists, and
        // onChange never fires for a value that was already there.
        consumePendingDeepLink()

        ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
        if !hasStartedAutoFetch, !usesMockMailbox {
            hasStartedAutoFetch = true
            triggerEmailTicketRefresh()
        }

        // Asked for here, at the app's own front door, rather than left to wait on
        // the Today list's first task: whichever train is running right now should
        // have its Live Activity up before the app is even navigated anywhere.
        let currentTrains = trains
        let currentStops = stops
        let currentSeats = seats
        Task {
            await TrainActivityManager.shared.sync(trains: currentTrains, stops: currentStops, seats: currentSeats)
        }
    }

    private func consumePendingDeepLink() {
        guard let url = deepLinks.pending else { return }
        deepLinks.pending = nil
        handleOpenURL(url)
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

        let seatID = components.queryItems?
            .first(where: { $0.name == "seatID" })?.value
            .flatMap(UUID.init(uuidString:))
        let wantsTicket = url.host == "view-ticket"
        let fromLiveActivity = components.queryItems?
            .first(where: { $0.name == "source" })?.value == TrainActivityLinks.liveActivitySource

        // A link can arrive over anything that happens to be open — a board sheet,
        // an import sheet — so clear the way to the journey it names.
        withAnimation(.snappy) {
            profileSheet = false
            addTrainSheet = false
            addPassSheet = false
            favoriteTrainsSheet = false
            emailImportSheet = false
            stationBoardSheet = false
            navigationPath = []
            selectedSection = .today
        }

        // Then push, and only then. Asking for the journey in the same turn races
        // the sheet on its way out and arrives at an empty details screen.
        pendingRouteTask?.cancel()
        pendingRouteTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            ticketSeatID = seatID
            showTicketView = wantsTicket
            scrollToNextStation = fromLiveActivity
            ticketTrainID = trainID
        }
    }

    /// The shortcut in the mail sheet when no mailbox is linked: close it, then open
    /// Profile on Email settings once the sheet is gone (two sheets can't swap in one turn).
    private func openEmailSettings() {
        emailImportSheet = false
        pendingRouteTask?.cancel()
        pendingRouteTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            profileOpensEmail = true
            profileSheet = true
        }
    }

    private func openEmailFetchSheet() {
        HapticFeedback.tap()
        let opensOnFullScan = isFetchingEmailTickets
            ? isFullEmailScan
            : !usesMockMailbox && showsProgressLayout(reloadAll: false)
        fetchSheetDetent = opensOnFullScan ? .medium : .large
        emailImportSheet = true
        // Opening the mailbox looks for what has arrived since the last sync and
        // nothing more: stored emails are never read a second time. Starting over
        // is what the refresh button inside the sheet is for.
        if !usesMockMailbox {
            triggerEmailTicketRefresh()
        }
    }

    private func triggerEmailTicketRefresh(reloadAll: Bool = false) {
        guard !isFetchingEmailTickets else { return }
        emailFetchTask = Task {
            await fetchEmailTickets(reloadAll: reloadAll)
        }
    }

    /// A single, already-synced mailbox with nothing found yet would otherwise show
    /// only a spinner: with no list to keep on screen, it gets the progress layout.
    private func showsProgressLayout(reloadAll: Bool) -> Bool {
        guard let profile = profiles.primary else { return false }
        return needsFullEmailScan(reloadAll: reloadAll) || EmailTicketSyncService.tickets(from: profile).isEmpty
    }

    private func needsFullEmailScan(reloadAll: Bool) -> Bool {
        guard let profile = profiles.primary else { return false }
        return reloadAll || profile.emails
            .filter(\.hasConfiguredCredentials)
            .contains(where: \.needsFullMailboxScan)
    }

    @MainActor
    private func fetchEmailTickets(reloadAll: Bool = false) async {
        guard let profile = profiles.primary else { return }
        isFullEmailScan = showsProgressLayout(reloadAll: reloadAll)
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
    /// The toolbar pulls the button in; a column of its own does not.
    var trailingInset: CGFloat = -4
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
        .padding(.trailing, trailingInset)
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

#Preview("Content View") {
    ContentView(usesMockMailbox: true, previewNow: PreviewMockData.moment)
        .modelContainer(PreviewMockData.makeContainer())
        .environment(\.locale, Locale(identifier: "it"))
}

/// The toolbar's mail icon: an envelope at rest, a turning spinner while fetching.
///
/// They are two views, both always there, faded one into the other. As one view
/// whose symbol changed, the spinner's turn in progress carried on after the
/// envelope had taken its place, so the envelope was seen to spin.
struct EmailFetchIcon: View {
    let isFetching: Bool

    var body: some View {
        ZStack {
            Image(systemName: "envelope")
                .opacity(isFetching ? 0 : 1)
                .scaleEffect(isFetching ? 0.6 : 1)
                .blur(radius: isFetching ? 2 : 0)

            Image(systemName: "progress.indicator")
                .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: isFetching)
                .opacity(isFetching ? 1 : 0)
                .scaleEffect(isFetching ? 1 : 0.6)
                .blur(radius: isFetching ? 0 : 2)
        }
        .foregroundStyle(Color.primary)
        .animation(.smooth, value: isFetching)
    }
}
