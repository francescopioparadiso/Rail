import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit

struct PassView: View {
    // MARK: - Types

    private enum PassFilter: CaseIterable {
        case all
        case active
        case expired

        struct EmptyState {
            let title: String
            let icon: String
            let description: String
        }

        var text: String {
            switch self {
            case .all:
                return String(localized: "All")
            case .active:
                return String(localized: "Active")
            case .expired:
                return String(localized: "Expired")
            }
        }

        var emptyState: EmptyState {
            switch self {
            case .all:
                EmptyState(
                    title: String(localized: "No passes"),
                    icon: "ticket.fill",
                    description: String(localized: "Add a new pass using the button below.")
                )
            case .active:
                EmptyState(
                    title: String(localized: "No active passes"),
                    icon: "checkmark.circle",
                    description: String(localized: "Change the filter to All or Expired to see other passes.")
                )
            case .expired:
                EmptyState(
                    title: String(localized: "No expired passes"),
                    icon: "clock.badge.exclamationmark",
                    description: String(localized: "Change the filter to All or Active to see other passes.")
                )
            }
        }
    }

    private enum PassFormPresentation: Identifiable {
        case new
        case edit(Pass)

        var id: String {
            switch self {
            case .new:
                return "new"
            case .edit(let pass):
                return pass.id.uuidString
            }
        }

        var passToEdit: Pass? {
            if case .edit(let pass) = self { return pass }
            return nil
        }
    }

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var modelContext
    @Query private var passes: [Pass]
    @Query private var profiles: [UserProfile]

    var openPrincipalPassQR: Bool = false

    @State private var displayedPasses: [Pass] = []
    /// Two-finger swipe on the list drives this; a non-empty set swaps the
    /// bottom bar over to the delete and share actions.
    @State private var selectedPassIDs: Set<PersistentIdentifier> = []
    @State private var editMode: EditMode = .inactive
    @State private var confirmingDelete = false
    @State private var knownPassIDs: Set<PersistentIdentifier> = []
    @State private var selectedYears: Set<Int> = []
    @State private var archive: PassArchiveFile?
    @State private var archiveError: String?
    @State private var searchText = ""
    @State private var passFilter: PassFilter = .all
    @State private var passFormPresentation: PassFormPresentation? = nil
    @State private var emailImportSheet = false
    @State private var fetchSheetDetent: PresentationDetent = .medium
    @State private var passSyncProgresses: [String: EmailPassSyncProgress] = [:]
    @State private var isFetchingEmailPasses = false
    @State private var showFetchResultCard = false
    @State private var fetchedPassesCount = 0
    @State private var emailFetchTask: Task<Void, Never>?
    @State private var hasStartedAutoFetch = false
    @State private var fetchingAccountEmails: [String] = []

    // MARK: - Computed

    private var fetchEmailsDownloaded: Int {
        passSyncProgresses.values.map(\.emailsDownloaded).reduce(0, +)
    }

    private var fetchEmailsFound: Int {
        passSyncProgresses.isEmpty ? fetchedPassesCount : passSyncProgresses.values.map(\.emailsFound).reduce(0, +)
    }

    private var showsFetchToolbarButton: Bool {
        isFetchingEmailPasses || showFetchResultCard
    }

    private var filteredPasses: [Pass] {
        displayedPasses.filter { matches($0, searchText: searchText) }
    }

    /// Passes grouped by the month they start in, newest first.
    private var groupedPassSections: [(title: String, passes: [Pass])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredPasses) { pass -> Date in
            let comps = calendar.dateComponents([.year], from: pass.start_date)
            return calendar.date(from: comps) ?? pass.start_date
        }
        return grouped.keys.sorted(by: >).map { key in
            (yearSectionTitle(for: key), (grouped[key] ?? []).sorted { $0.start_date > $1.start_date })
        }
    }

    private var isFiltering: Bool { passFilter != .all || !selectedYears.isEmpty }

    /// Years covered by the saved passes, newest first.
    private var availableYears: [Int] {
        let calendar = Calendar.current
        return Set(passes.map { calendar.component(.year, from: $0.start_date) }).sorted(by: >)
    }

    private var isSelecting: Bool { editMode.isEditing }

    /// Only what's on screen: a filter or a search narrows what "all" means.
    private var selectablePassIDs: Set<PersistentIdentifier> {
        Set(filteredPasses.map(\.persistentModelID))
    }

    private var allPassesSelected: Bool {
        let selectable = selectablePassIDs
        return !selectable.isEmpty && selectable.isSubset(of: selectedPassIDs)
    }

    private var selectionActionTitle: LocalizedStringKey {
        guard isSelecting else { return "Select" }
        return allPassesSelected ? "Deselect All" : "Select All"
    }

    private var selectedPasses: [Pass] {
        filteredPasses.filter { selectedPassIDs.contains($0.persistentModelID) }
    }

    private var fetchProgressValue: Double {
        if passSyncProgresses.isEmpty {
            return -2.0
        }
        if passSyncProgresses.values.allSatisfy({ $0.stage == .searching }) {
            return -1.0
        }
        if passSyncProgresses.values.allSatisfy({ $0.stage == .finished }) {
            return Double(fetchEmailsFound + 1)
        }
        return Double(fetchEmailsDownloaded)
    }

    private var fetchProgressTitle: String {
        if passSyncProgresses.isEmpty {
            return String(localized: "Connecting…")
        }
        if passSyncProgresses.values.allSatisfy({ $0.stage == .searching }) {
            return String(localized: "Searching…")
        }
        if passSyncProgresses.values.allSatisfy({ $0.stage == .finished }) {
            return String(localized: "Finishing up…")
        }
        let totalFound = fetchEmailsFound
        let downloaded = fetchEmailsDownloaded
        let percentage = totalFound > 0 ? Double(downloaded) / Double(totalFound) : 0.0
        return String(localized: "Fetching \(Int(percentage * 100))%")
    }

    private var fetchProgressSublabel: String? {
        if passSyncProgresses.isEmpty {
            return String(localized: "This can take a moment on the first scan.")
        }
        return nil
    }

    private var computedAccountProgresses: [AccountSyncProgress] {
        fetchingAccountEmails.map { email in
            let progress = passSyncProgresses[email]
            return AccountSyncProgress(
                email: email,
                found: progress?.emailsFound ?? 0,
                processed: progress?.emailsDownloaded ?? 0
            )
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredPasses.isEmpty && !isFetchingEmailPasses && !showFetchResultCard {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(Color.secondary)
                        .fontDesign(appFontDesign)
                } else if passes.isEmpty {
                    ContentUnavailableView(
                        "No passes added",
                        systemImage: "ticket.fill",
                        description: Text("Add a new pass using the button below.")
                    )
                    .foregroundStyle(.secondary)
                    .fontDesign(appFontDesign)
                } else if filteredPasses.isEmpty {
                    ContentUnavailableView {
                        Label(passFilter.emptyState.title, systemImage: passFilter.emptyState.icon)
                    } description: {
                        Text(passFilter.emptyState.description)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                } else {
                    List(selection: $selectedPassIDs) {
                        ForEach(groupedPassSections, id: \.title) { section in
                            Section {
                                ForEach(section.passes) { pass in
                                    passRow(pass: pass)
                                        .tag(pass.persistentModelID)
                                        // suppress the red minus beside the selection circle
                                        .deleteDisabled(isSelecting)
                                }
                                .onDelete { offsets in
                                    deletePasses(at: offsets, from: section.passes)
                                }
                            } header: {
                                Text(section.title)
                            } footer: {
                                if section.title == groupedPassSections.last?.title {
                                    Text("Swipe to the right to add the QR code to the widget")
                                }
                            }
                            .fontDesign(appFontDesign)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle("Passes")
            .toolbar {
                // the close button doubles as the way out of selection mode,
                // which frees the trailing slot up for "Select All"
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if isSelecting {
                            HapticFeedback.tap()
                            endSelection()
                        } else {
                            dismiss()
                        }
                    } label: {
                        if isSelecting {
                            Text("Cancel")
                                .fontDesign(appFontDesign)
                        } else {
                            Image(systemName: "xmark")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticFeedback.tap()
                        withAnimation(.snappy) {
                            if isSelecting {
                                toggleSelectAll()
                            } else {
                                editMode = .active
                            }
                        }
                    } label: {
                        Text(selectionActionTitle)
                            .contentTransition(.numericText())
                            .fontDesign(appFontDesign)
                    }
                    .disabled(isSelecting && filteredPasses.isEmpty)
                }

                if !isSelecting, showsFetchToolbarButton {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openEmailFetchSheet()
                        } label: {
                            emailFetchToolbarLabel
                        }
                        .fontDesign(appFontDesign)
                    }
                }

                if isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            HapticFeedback.tap()
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(selectedPassIDs.isEmpty)
                        .confirmationDialog(
                            "Delete \(selectedPassIDs.count) \(selectedPassIDs.count == 1 ? "pass" : "passes")?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) { deleteSelectedPasses() }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("This can't be undone.")
                        }
                    }

                    ToolbarSpacer(.flexible, placement: .bottomBar)

                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            shareSelectedPasses()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedPasses.isEmpty || selectedPasses.allSatisfy { ($0.pdf?.isEmpty ?? true) })
                    }
                }

                if !isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        if isFiltering {
                            ControlGroup {
                                Button(role: .destructive) {
                                    HapticFeedback.select()
                                    withAnimation(.snappy) {
                                        passFilter = .all
                                        selectedYears = []
                                        refreshDisplayedPasses()
                                    }
                                } label: {
                                    Label("Clear filter", systemImage: "trash")
                                }
                            }
                        }

                        Section("Status") {
                            ForEach([PassFilter.active, PassFilter.expired], id: \.self) { filter in
                                Button {
                                    HapticFeedback.select()
                                    withAnimation(.snappy) {
                                        // tapping the active one clears it
                                        passFilter = passFilter == filter ? .all : filter
                                        refreshDisplayedPasses()
                                    }
                                } label: {
                                    Label {
                                        Text(filter.text)
                                    } icon: {
                                        if passFilter == filter { Image(systemName: "checkmark") }
                                    }
                                    .foregroundStyle(passFilter == filter ? Color.blue : Color.primary)
                                }
                            }
                        }

                        if availableYears.count > 1 {
                            Section("Year") {
                                ForEach(availableYears, id: \.self) { year in
                                    Button {
                                        HapticFeedback.select()
                                        withAnimation(.snappy) {
                                            if selectedYears.contains(year) {
                                                selectedYears.remove(year)
                                            } else {
                                                selectedYears.insert(year)
                                            }
                                            refreshDisplayedPasses()
                                        }
                                    } label: {
                                        Label {
                                            Text(verbatim: String(year))
                                        } icon: {
                                            if selectedYears.contains(year) { Image(systemName: "checkmark") }
                                        }
                                        .foregroundStyle(selectedYears.contains(year) ? Color.blue : Color.primary)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.horizontal.3.decrease")
                                .font(isFiltering ? .title2 : .headline)
                                .padding(.horizontal, isFiltering ? -2 : 0)
                                .foregroundStyle(isFiltering ? .blue : .primary)
                        }
                        .fontDesign(appFontDesign)
                    }
                }
                
                ToolbarSpacer(.fixed, placement: .bottomBar)

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        HapticFeedback.confirm()
                        passFormPresentation = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                }
            }
            .searchable(text: $searchText, prompt: "Search passes")
            .sheet(item: $archive) { file in
                ActivityShareSheet(items: [file.url]) {
                    try? FileManager.default.removeItem(at: file.url)
                    endSelection()
                }
            }
            .alert("Couldn't share", isPresented: Binding(
                get: { archiveError != nil },
                set: { if !$0 { archiveError = nil } }
            )) {
                Button("OK", role: .cancel) { archiveError = nil }
            } message: {
                Text(archiveError ?? "")
            }
            .sheet(item: $passFormPresentation) { presentation in
                PassFormSheet(passToEdit: presentation.passToEdit) {
                    refreshDisplayedPasses()
                }
            }
            .sheet(isPresented: $emailImportSheet) {
                NavigationStack {
                    Group {
                        if isFetchingEmailPasses {
                            EmailSyncProgressView(
                                isFetching: isFetchingEmailPasses,
                                progressTitle: fetchProgressTitle,
                                globalPercentage: fetchProgressValue > 0 ? (fetchProgressValue / Double(max(1, fetchEmailsFound))) * 100 : 0,
                                accountProgresses: computedAccountProgresses,
                                progressSublabel: fetchProgressSublabel
                            ) {
                                emailFetchTask?.cancel()
                                emailFetchTask = Task {
                                    await fetchEmailPasses(reloadAll: true)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            EmailPassImportView(
                                autoScanOnAppear: false,
                                onPassAdded: { refreshDisplayedPasses() },
                                onReloadRequested: {
                                    triggerEmailPassRefresh(reloadAll: true)
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFetchingEmailPasses)
                }
                .presentationDetents(
                    isFetchingEmailPasses ? [.medium] : [.large],
                    selection: $fetchSheetDetent
                )
                .presentationDragIndicator(.hidden)
                .presentationBackground(appBackgroundColor)
                .onChange(of: isFetchingEmailPasses) { _, isFetching in
                    withAnimation(.snappy) {
                        fetchSheetDetent = isFetching ? .medium : .large
                    }
                }
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .onAppear {
            // seed so the first insert is the only thing treated as new
            knownPassIDs = Set(passes.map(\.persistentModelID))
            refreshDisplayedPasses()
            if !hasStartedAutoFetch {
                hasStartedAutoFetch = true
                triggerEmailPassRefresh()
            }
            if openPrincipalPassQR, let principal = passes.first(where: \.is_principal) {
                passFormPresentation = .edit(principal)
            }
        }
        .onChange(of: passes.count) { _, _ in revealNewPassesIfHidden() }
        .onChange(of: passFilter) { _, _ in refreshDisplayedPasses() }
        .onDisappear {
            emailFetchTask?.cancel()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func passRow(pass: Pass) -> some View {
        let isActive = pass.expiry_date >= Calendar.current.startOfDay(for: Date())
        let timeRemaining: String = {
            if !isActive {
                let dateString = pass.expiry_date.formatted(.dateTime.day().month().year())
                return String(localized: "Expired on \(dateString)")
            }

            let totalDays = Calendar.current.dateComponents([.day], from: Date(), to: pass.expiry_date).day ?? 0
            if totalDays == 0 { return String(localized: "Expires today") }
            if totalDays == 1 { return String(localized: "Expires tomorrow") }

            return String(localized: "Expires in \(totalDays) days")
        }()

        let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
        let statusColor: Color = pass.is_principal ? amber : (isActive ? .green : .red)
        let statusIcon: String = pass.is_principal ? "star.fill" : (isActive ? "checkmark.circle.fill" : "xmark.circle.fill")

        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.largeTitle)
                .foregroundStyle(statusColor)
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))

            VStack(alignment: .leading, spacing: 4) {
                // What a pass is worth is the stretch of time it covers, so that
                // leads; its name says which kind of pass bought that stretch.
                Text(PassValidityPeriod.text(
                    name: pass.name,
                    start: pass.start_date,
                    end: pass.expiry_date
                ))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

                Text(pass.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(timeRemaining)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 8)

            if !pass.price.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(pass.price)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.tap()
            // while selecting, the whole row toggles the pass; the tick alone was
            // the only reliable target because this gesture swallowed the rest
            if isSelecting {
                withAnimation(.snappy) {
                    let id = pass.persistentModelID
                    if selectedPassIDs.contains(id) {
                        selectedPassIDs.remove(id)
                    } else {
                        selectedPassIDs.insert(id)
                    }
                }
            } else {
                passFormPresentation = .edit(pass)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isActive {
                Button {
                    HapticFeedback.impactHeavy()
                    withAnimation(.snappy) {
                        if pass.is_principal {
                            pass.is_principal = false
                        } else {
                            for p in passes {
                                p.is_principal = false
                            }
                            pass.is_principal = true
                        }

                        try? modelContext.save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                } label: {
                    Label(pass.is_principal ? "Remove Principal" : "Set Principal", systemImage: pass.is_principal ? "star.slash.fill" : "star.fill")
                }
                .tint(Color(red: 1.0, green: 0.75, blue: 0.0))
            }
        }
    }

    /// Icon only: the progress wording lives in the fetch sheet, so repeating it
    /// in the toolbar just crowded the navigation bar.
    @ViewBuilder
    private var emailFetchToolbarLabel: some View {
        let isFetching = isFetchingEmailPasses

        Group {
            if isFetching {
                Image(systemName: "progress.indicator")
                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous))
            } else {
                Image(systemName: "envelope")
            }
        }
        .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
        .foregroundStyle(Color.primary)
        .font(.callout).fontWeight(.medium).fontDesign(appFontDesign)
        .animation(.snappy, value: isFetching)
    }

    // MARK: - Actions

    /// Drops the status filter when a pass arrives that it would hide — adding an
    /// expired pass while "Active" is on would otherwise look like nothing happened.
    private func revealNewPassesIfHidden() {
        let current = Set(passes.map(\.persistentModelID))
        let added = current.subtracting(knownPassIDs)
        knownPassIDs = current

        if passFilter != .all,
           added.contains(where: { id in
               guard let pass = passes.first(where: { $0.persistentModelID == id }) else { return false }
               return !matchesStatusFilter(pass)
           }) {
            withAnimation(.snappy) { passFilter = .all }
        }
        refreshDisplayedPasses()
    }

    private func matchesStatusFilter(_ pass: Pass) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        switch passFilter {
        case .all: return true
        case .active: return pass.expiry_date >= startOfToday
        case .expired: return pass.expiry_date < startOfToday
        }
    }

    private func refreshDisplayedPasses() {
        let all = passes.sorted {
            if $0.start_date != $1.start_date {
                return $0.start_date > $1.start_date
            }
            return $0.expiry_date > $1.expiry_date
        }
        let startOfToday = Calendar.current.startOfDay(for: Date())

        let byYear = selectedYears.isEmpty ? all : all.filter {
            selectedYears.contains(Calendar.current.component(.year, from: $0.start_date))
        }

        displayedPasses = switch passFilter {
        case .all:
            byYear
        case .active:
            byYear.filter { $0.expiry_date >= startOfToday }
        case .expired:
            byYear.filter { $0.expiry_date < startOfToday }
        }
    }

    private func matches(_ pass: Pass, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        if pass.name.lowercased().contains(query) {
            return true
        }

        let expiryDate = pass.expiry_date
        let startDate = pass.start_date
        let searchableDates = [
            startDate.formatted(.dateTime.day().month().year()),
            startDate.formatted(date: .abbreviated, time: .omitted),
            startDate.formatted(date: .numeric, time: .omitted),
            expiryDate.formatted(.dateTime.day().month().year()),
            expiryDate.formatted(date: .abbreviated, time: .omitted),
            expiryDate.formatted(date: .long, time: .omitted),
            expiryDate.formatted(date: .numeric, time: .omitted),
            expiryDate.formatted(.dateTime.year()),
            expiryDate.formatted(.dateTime.month(.wide)),
            expiryDate.formatted(.dateTime.month(.abbreviated)),
            expiryDate.formatted(.dateTime.day()),
        ]

        return searchableDates.contains { $0.lowercased().contains(query) }
    }

    private func endSelection() {
        withAnimation(.snappy) {
            selectedPassIDs.removeAll()
            editMode = .inactive
        }
    }

    private func toggleSelectAll() {
        let selectable = selectablePassIDs
        if allPassesSelected {
            selectedPassIDs.subtract(selectable)
        } else {
            selectedPassIDs.formUnion(selectable)
        }
    }

    private func deleteSelectedPasses() {
        let doomed = selectedPasses
        guard !doomed.isEmpty else { return }
        HapticFeedback.impactHeavy()
        withAnimation(.snappy) {
            for pass in doomed { modelContext.delete(pass) }
            selectedPassIDs.removeAll()
            editMode = .inactive
        }
        try? modelContext.save()
        refreshDisplayedPasses()
        reloadWidgetTimelines()
    }

    private func shareSelectedPasses() {
        let chosen = selectedPasses
        guard !chosen.isEmpty else { return }
        HapticFeedback.confirm()
        do {
            let result = try PassPDFArchive.makeArchive(from: chosen)
            archive = PassArchiveFile(url: result.url)
        } catch {
            archiveError = error.localizedDescription
        }
    }

    private func deletePasses(at offsets: IndexSet, from list: [Pass]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        refreshDisplayedPasses()
    }

    private func openEmailFetchSheet() {
        HapticFeedback.tap()
        fetchSheetDetent = isFetchingEmailPasses ? .medium : .large
        emailImportSheet = true
    }

    private func triggerEmailPassRefresh(reloadAll: Bool = false) {
        guard !isFetchingEmailPasses else { return }
        emailFetchTask = Task {
            await fetchEmailPasses(reloadAll: reloadAll)
        }
    }

    @MainActor
    private func fetchEmailPasses(reloadAll: Bool = false) async {
        guard let profile = profiles.primary else { return }
        withAnimation(.snappy) {
            isFetchingEmailPasses = true
            showFetchResultCard = false
        }
        passSyncProgresses = [:]

        let configured = profile.emails.filter(\.hasConfiguredCredentials)
        fetchingAccountEmails = configured.map(\.email)
        let accounts = await validatedEmailAccounts(from: profile)
        fetchingAccountEmails = accounts.map(\.email)

        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { @MainActor in
                    do {
                        _ = try await EmailPassSyncService.syncAccount(
                            accountID: account.id,
                            profile: profile,
                            modelContext: modelContext,
                            reloadAll: reloadAll
                        ) { progress in
                            passSyncProgresses[progress.accountEmail] = progress
                        }
                    } catch {
                    }
                }
            }
        }

        fetchedPassesCount = passSyncProgresses.values.map(\.emailsFound).reduce(0, +)
        if fetchedPassesCount == 0 {
            fetchedPassesCount = EmailPassSyncService.passes(from: profile).count
        }
        if !Task.isCancelled {
            withAnimation(.snappy) {
                isFetchingEmailPasses = false
                showFetchResultCard = true
            }
        }
    }

}

#Preview("Pass View - Full") {
    let schema = Schema([Pass.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    container.mainContext.insert(
        UserProfile(
            name: "Francesco",
            emails: [
                Emails(
                    provider: .google,
                    email: PreviewCredentials.googleEmail,
                    appPassword: PreviewCredentials.googleAppPassword
                )
            ]
        )
    )

    let pass1 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        is_principal: false,
        image: UIImage(named: "sample_code")?.pngData()
    )
    let pass2 = Pass(
        id: UUID(),
        name: "Weekly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        is_principal: false,
        image: UIImage(named: "sample_code")?.pngData()
    )
    let pass3 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: UIImage(named: "sample_code")?.pngData()
    )

    container.mainContext.insert(pass1)
    container.mainContext.insert(pass2)
    container.mainContext.insert(pass3)

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            PassView()
                .modelContainer(container)
        }
}

#Preview("Pass View - Empty") {
    let schema = Schema([Pass.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    container.mainContext.insert(
        UserProfile(
            name: "Francesco",
            emails: [
                Emails(
                    provider: .google,
                    email: PreviewCredentials.googleEmail,
                    appPassword: PreviewCredentials.googleAppPassword
                )
            ]
        )
    )

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            PassView()
                .modelContainer(container)
        }
}
