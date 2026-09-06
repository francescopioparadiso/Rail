import SwiftUI
import SwiftData

struct PreloadedEmailTicketItem: Identifiable {
    let id: UUID
    let ticket: EmailContent
    let accountEmail: String
    var state: PreloadState
}

struct EmailTrainImportView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var profiles: [UserProfile]
    @Query private var trains: [Train]

    var autoScanOnAppear: Bool = true
    var onTrainAdded: (() -> Void)? = nil
    var onReloadRequested: (() -> Void)? = nil

    /// Previews and screenshots only. Their tickets are invented, so there is no
    /// journey for `EmailTrainService.loadTrain` to find and every row would stay
    /// dimmed on a lookup that cannot succeed. Treat them as already resolved.
    var previewTicketsAreReady: Bool = false

    @State private var preloadedTickets: [PreloadedEmailTicketItem] = []
    @State private var preparedTrains: [UUID: PreparedEmailTrain] = [:]
    @State private var isWorking = false
    @State private var isPreparing = false
    @State private var hasStarted = false
    @State private var syncError: String?
    @State private var syncProgress: EmailTicketSyncProgress?
    @State private var accountProgresses: [AccountSyncProgress] = []
    @State private var totalNewTickets = 0
    @State private var preparedCount = 0
    @State private var preparationTotal = 0
    @State private var syncTask: Task<Void, Never>?
    @State private var searchText = ""
    /// Mailboxes whose tickets are shown. Empty means every account.
    @State private var selectedAccounts: Set<String> = []

    // MARK: - Computed

    private var linkedAccounts: [Emails] {
        profiles.primary?.emails ?? []
    }

    private var isSyncFinished: Bool {
        syncProgress?.stage == .finished && !isPreparing
    }

    private var globalPercentage: Int {
        let totalFound = accountProgresses.reduce(0) { $0 + $1.found }
        let totalProcessed = accountProgresses.reduce(0) { $0 + $1.processed }
        guard totalFound > 0 else { return 0 }
        return min(100, Int((Double(totalProcessed) / Double(totalFound)) * 100))
    }

    /// The mailboxes these tickets came from, in profile order.
    private var availableAccounts: [String] {
        let present = Set(preloadedTickets.map(\.accountEmail))
        return (profiles.primary?.emails.map(\.email) ?? []).filter(present.contains)
    }

    private var isFiltering: Bool { !selectedAccounts.isEmpty }

    private var filteredTickets: [PreloadedEmailTicketItem] {
        var items = preloadedTickets
        if !selectedAccounts.isEmpty {
            items = items.filter { selectedAccounts.contains($0.accountEmail) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { matches($0.ticket, query: query) }
    }

    private var groupedTicketSections: [(title: String, items: [PreloadedEmailTicketItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTickets) { item -> Date in
            let date = item.ticket.departureDate ?? item.ticket.date
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? date
        }

        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { lhs, rhs in
                let lhsDate = lhs.ticket.departureDate ?? lhs.ticket.date
                let rhsDate = rhs.ticket.departureDate ?? rhs.ticket.date
                return lhsDate > rhsDate
            }
            return (monthSectionTitle(for: key, locale: locale), items)
        }
    }

    private var progressLabel: String {
        if isPreparing {
            return String(localized: "Preparing trains…")
        }
        guard let progress = syncProgress else {
            return String(localized: "Connecting…")
        }
        switch progress.stage {
        case .searching:
            return String(localized: "Searching…")
        case .downloading:
            return String(localized: "Fetching \(globalPercentage)%")
        case .fetchingDetails:
            return String(localized: "Details \(progress.detailsCompleted) of \(progress.detailsTotal)")
        case .finished:
            return totalNewTickets == 0
                ? String(localized: "No new tickets")
                : "\(totalNewTickets) new"
        }
    }

    private var progressSublabel: String {
        if isPreparing {
            return String(
                localized: "Prepared \(preparedCount) of \(preparationTotal) trains"
            )
        }
        guard let progress = syncProgress else {
            return String(localized: "This can take a moment on the first scan.")
        }
        switch progress.stage {
        case .searching:
            return ""
        case .downloading, .fetchingDetails:
            return ""
        case .finished:
            return ""
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if linkedAccounts.isEmpty {
                    ContentUnavailableView(
                        "No email linked",
                        systemImage: "bell.slash",
                        description: Text("Add an email account in Profile → Email to import Trenitalia check-in tickets.")
                    )
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                } else if isWorking && preloadedTickets.isEmpty {
                    progressView
                } else if preloadedTickets.isEmpty {
                    ContentUnavailableView {
                        Label("No tickets found", systemImage: "envelope")
                    } description: {
                        if let syncError {
                            Text(syncError)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("No Trenitalia self-check-in emails were found for your linked accounts.")
                                .multilineTextAlignment(.center)
                        }
                    } actions: {
                        Button {
                            HapticFeedback.confirm()
                            if let onReloadRequested {
                                onReloadRequested()
                            } else {
                                beginScan(reloadAll: true)
                            }
                        } label: {
                            Label("Scan again emails", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .refreshable {
                        await refreshMailbox(reloadAll: false)
                    }
                    // red only when the scan itself failed; an empty mailbox is not an error
                    .foregroundStyle(syncError == nil ? Color.secondary : Color.red)
                    .fontDesign(appFontDesign)
                } else {
                    List {
                        if isWorking {
                            Section {
                                progressView
                                    .frame(maxWidth: .infinity)
                                    .listRowBackground(Color.clear)
                            }
                        }

                        if let syncError {
                            Section {
                                Label(syncError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }

                        if groupedTicketSections.isEmpty {
                            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !query.isEmpty {
                                Section {
                                    ContentUnavailableView.search(text: searchText)
                                        .foregroundStyle(Color.secondary)
                                        .listRowBackground(Color.clear)
                                }
                            } else if isFiltering {
                                Section {
                                    ContentUnavailableView(
                                        "No tickets",
                                        systemImage: "line.3.horizontal.decrease.circle",
                                        description: Text("No tickets from the selected mailbox.")
                                    )
                                    .foregroundStyle(Color.secondary)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        ForEach(groupedTicketSections, id: \.title) { section in
                            Section {
                                ForEach(section.items) { item in
                                    let isLoading = item.state == .loading
                                    // Eligibility runs by the departure day, not the departure
                                    // minute: a train that left ten minutes ago is one you may
                                    // well be sitting on, so it stays addable all day.
                                    let canAdd = item.state == .ready && item.ticket.isImportEligible

                                    Button {
                                        addTicket(item)
                                    } label: {
                                        EmailTicketRow(ticket: item.ticket, isLoading: isLoading)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canAdd)
                                    .opacity((canAdd || isLoading) ? 1 : 0.5)
                                }
                            } header: {
                                Text(section.title)
                            }
                            .fontDesign(appFontDesign)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(32)
                    .scrollIndicators(.visible)
                    .refreshable {
                        await refreshMailbox(reloadAll: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackgroundColor)
            .navigationTitle("From Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticFeedback.confirm()
                        if let onReloadRequested {
                            onReloadRequested()
                        } else {
                            beginScan(reloadAll: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isWorking)
                }

                if availableAccounts.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        accountFilterMenu
                    }
                }

                ToolbarSpacer(.fixed, placement: .bottomBar)

                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .searchable(text: $searchText, prompt: "Search")
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .presentationBackground(appBackgroundColor)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            if autoScanOnAppear {
                beginScan(reloadAll: false)
            } else {
                loadTicketsFromProfile()
                guard !previewTicketsAreReady else { return }
                syncTask = Task {
                    await prepareEligibleTrains()
                }
            }
        }
        .onDisappear { syncTask?.cancel() }
    }

    // MARK: - Subviews

    /// Narrows the list to one mailbox, for people importing from more than one.
    private var accountFilterMenu: some View {
        Menu {
            if isFiltering {
                ControlGroup {
                    Button(role: .destructive) {
                        HapticFeedback.select()
                        withAnimation(.snappy) { selectedAccounts = [] }
                    } label: {
                        Label("Clear filter", systemImage: "trash")
                    }
                }
            }

            Section("Email") {
                ForEach(availableAccounts, id: \.self) { account in
                    Button {
                        HapticFeedback.select()
                        withAnimation(.snappy) {
                            // tapping the selected one clears it
                            if selectedAccounts.contains(account) {
                                selectedAccounts.remove(account)
                            } else {
                                selectedAccounts.insert(account)
                            }
                        }
                    } label: {
                        Label {
                            // long addresses lose their middle, keeping the name and
                            // the domain — the two halves that tell accounts apart
                            Text(account)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            if selectedAccounts.contains(account) { Image(systemName: "checkmark") }
                        }
                        .foregroundStyle(selectedAccounts.contains(account) ? Color.blue : Color.primary)
                    }
                }
            }
        } label: {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.horizontal.3.decrease")
                .font(isFiltering ? .title2 : .headline)
                .padding(.horizontal, isFiltering ? -2 : 0)
                .foregroundStyle(isFiltering ? .blue : .primary)
                .fontDesign(appFontDesign)
        }
    }

    private var progressView: some View {
        EmailSyncProgressView(
            isFetching: !isSyncFinished,
            progressTitle: progressLabel,
            globalPercentage: Double(globalPercentage),
            accountProgresses: accountProgresses,
            progressSublabel: progressSublabel.isEmpty ? nil : progressSublabel
        ) {
            if let onReloadRequested {
                onReloadRequested()
            } else {
                beginScan(reloadAll: true)
            }
        }
    }

    // MARK: - Actions

    /// Matches train number, either station, and the departure date or time.
    private func matches(_ ticket: EmailContent, query: String) -> Bool {
        var haystack = [ticket.trainNumber, ticket.departureStation, ticket.arrivalStation, ticket.price]
        if let departure = ticket.departureDate {
            haystack.append(departure.formatted(.dateTime.day().month().year()))
            haystack.append(departure.formatted(date: .abbreviated, time: .omitted))
            haystack.append(departure.formatted(.dateTime.hour().minute()))
        }
        return haystack.contains { $0.lowercased().contains(query) }
    }

    private func beginScan(reloadAll: Bool) {
        guard !isWorking else { return }
        syncTask = Task {
            await scanMailbox(reloadAll: reloadAll)
        }
    }

    private func refreshMailbox(reloadAll: Bool) async {
        if isWorking, let syncTask {
            await syncTask.value
            return
        }
        let task = Task {
            await scanMailbox(reloadAll: reloadAll)
        }
        syncTask = task
        await task.value
    }

    @MainActor
    private func scanMailbox(reloadAll: Bool) async {
        guard let profile = profiles.primary else { return }

        isWorking = true
        defer {
            isPreparing = false
            isWorking = false
        }
        isPreparing = false
        syncError = nil
        syncProgress = nil
        accountProgresses = []
        totalNewTickets = 0
        preparedCount = 0
        preparationTotal = 0
        if reloadAll {
            preloadedTickets = []
            preparedTrains = [:]
        }
        var errors: [String] = []

        // Pre-populate account rows so all appear immediately
        let configuredAccounts = profile.emails.filter(\.hasConfiguredCredentials)
        accountProgresses = configuredAccounts.map {
            AccountSyncProgress(email: $0.email, found: 0, processed: 0)
        }

        for (accountIndex, account) in configuredAccounts.enumerated() {
            guard !Task.isCancelled else { return }
            do {
                let result = try await EmailTicketSyncService.syncAccount(
                    accountID: account.id,
                    profile: profile,
                    modelContext: modelContext,
                    reloadAll: reloadAll
                ) { progress in
                    syncProgress = progress
                    if progress.stage == .downloading || progress.stage == .fetchingDetails {
                        accountProgresses[accountIndex].found = progress.emailsFound
                        accountProgresses[accountIndex].processed = progress.emailsDownloaded
                    }
                    if let warning = progress.latestWarning {
                        syncError = warning
                    }
                }
                // Mark this account fully processed
                accountProgresses[accountIndex].processed = accountProgresses[accountIndex].found
                totalNewTickets += (syncProgress?.newTicketsCount ?? 0)
                errors.append(contentsOf: result.warnings.map { "\(account.email): \($0)" })
            } catch {
                errors.append("\(account.email): \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }
        if !errors.isEmpty {
            syncError = errors.joined(separator: "\n")
        }
        loadTicketsFromProfile()
        await prepareEligibleTrains()
    }

    @MainActor
    /// Drops any filter whose mailbox no longer has tickets, so a rescan can't
    /// leave the list mysteriously empty.
    private func pruneAccountFilter() {
        guard !selectedAccounts.isEmpty else { return }
        let present = Set(preloadedTickets.map(\.accountEmail))
        let surviving = selectedAccounts.intersection(present)
        if surviving != selectedAccounts {
            withAnimation(.snappy) { selectedAccounts = surviving }
        }
    }

    private func loadTicketsFromProfile() {
        guard let profile = profiles.primary else {
            preloadedTickets = []
            preparedTrains = [:]
            return
        }

        let tickets = EmailTicketSyncService.tickets(from: profile)
        // Show every ticket using email-parsed fields immediately. Only tickets
        // departing today or later are prepared for import; the rest are listed as
        // history and never reach for their check-in link.
        preloadedTickets = tickets.map { account, ticket in
            let state: PreloadState
            if ticket.isImportEligible {
                state = previewTicketsAreReady ? .ready : .loading
            } else {
                state = .unavailable
            }
            return PreloadedEmailTicketItem(
                id: ticket.id,
                ticket: ticket,
                accountEmail: account.email,
                state: state
            )
        }
        preparedTrains = [:]
        pruneAccountFilter()
    }

    @MainActor
    private func prepareEligibleTrains() async {
        // Details are fetched through the check-in link only for journeys still to
        // come — today's included, however late in the day it is.
        let ticketsToPrepare = preloadedTickets.filter {
            $0.ticket.isImportEligible && $0.state == .loading
        }
        isPreparing = !ticketsToPrepare.isEmpty
        preparationTotal = ticketsToPrepare.count
        preparedCount = 0

        guard let profile = profiles.primary else { return }

        for item in ticketsToPrepare {
            guard !Task.isCancelled else { return }
            var ticket = item.ticket
            
            if !ticket.hasLoadedDetails {
                if let emailIndex = profile.emails.firstIndex(where: { $0.email == item.accountEmail }) {
                    do {
                        try await EmailTicketSyncService.fetchAndSaveTicketDetails(
                            for: ticket.id,
                            checkInID: ticket.link,
                            emailIndex: emailIndex,
                            profile: profile,
                            modelContext: modelContext
                        )
                        if let updated = profile.emails[emailIndex].content.first(where: { $0.id == ticket.id }) {
                            ticket = updated
                        }
                    } catch {
                        print("Failed to fetch details for \(ticket.id): \(error)")
                    }
                }
            }
            
            let prepared = await EmailTrainService.loadTrain(for: ticket)

            guard !Task.isCancelled else { return }
            guard let index = preloadedTickets.firstIndex(where: { $0.id == ticket.id }) else { continue }

            if let prepared {
                let passengers = resolvedPassengers(for: ticket, prepared: prepared)
                preparedTrains[ticket.id] = PreparedEmailTrain(
                    prepared: prepared.prepared,
                    passengers: passengers
                )
                preloadedTickets[index].state = .ready
            } else {
                preloadedTickets[index].state = .unavailable
            }
            preparedCount += 1
        }

        isPreparing = false
    }

    private func addTicket(_ item: PreloadedEmailTicketItem) {
        guard item.state == .ready,
              item.ticket.isImportEligible,
              let prepared = preparedTrains[item.id] else { return }

        HapticFeedback.confirm()
        let passengers = resolvedPassengers(for: item.ticket, prepared: prepared)
        EmailTrainService.savePreparedTrain(
            PreparedEmailTrain(prepared: prepared.prepared, passengers: passengers),
            sourceTicketID: item.id,
            modelContext: modelContext,
            profile: profiles.primary
        )
        onTrainAdded?()
        dismiss()
    }

    private func resolvedPassengers(
        for ticket: EmailContent,
        prepared: PreparedEmailTrain
    ) -> [EmailContentPassenger] {
        var passengers = ticket.passengers.isEmpty ? prepared.passengers : ticket.passengers
        let profileName = profiles.primary?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if passengers.count == 1, !profileName.isEmpty {
            passengers[0].name = profileName
        }
        return passengers
    }
}

private struct EmailTrainImportPreview: View {
    // MARK: - Properties

    let container: ModelContainer

    // MARK: - Body

    var body: some View {
        EmailTrainImportView(autoScanOnAppear: false, previewTicketsAreReady: true)
            .modelContainer(container)
    }
}

#Preview("Email Train Import View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self,
        configurations: config
    )

    container.mainContext.insert(
        UserProfile(
            name: "Francesco",
            photo: PreviewMockData.profilePhoto(),
            emails: [
                PreviewMockData.appleAccount(),
                PreviewMockData.googleAccount()
            ]
        )
    )

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            EmailTrainImportPreview(container: container)
        }
}
