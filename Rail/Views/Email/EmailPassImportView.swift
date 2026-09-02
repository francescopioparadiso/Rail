import SwiftUI
import SwiftData
import WidgetKit

struct PreloadedEmailPassItem: Identifiable {
    let id: UUID
    let pass: EmailPassContent
    let accountEmail: String
}

struct EmailPassImportView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var passes: [Pass]

    var autoScanOnAppear: Bool = true
    var onPassAdded: (() -> Void)? = nil
    var onReloadRequested: (() -> Void)? = nil

    @State private var preloadedPasses: [PreloadedEmailPassItem] = []
    @State private var isWorking = false
    @State private var hasStarted = false
    @State private var syncError: String?
    @State private var syncProgress: EmailPassSyncProgress?
    @State private var accountProgresses: [AccountSyncProgress] = []
    @State private var syncTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var showSaveAllConfirmation = false

    // MARK: - Computed

    private var isSyncFinished: Bool {
        syncProgress?.stage == .finished
    }

    private var globalPercentage: Int {
        let totalFound = accountProgresses.reduce(0) { $0 + $1.found }
        let totalProcessed = accountProgresses.reduce(0) { $0 + $1.processed }
        guard totalFound > 0 else { return 0 }
        return min(100, Int((Double(totalProcessed) / Double(totalFound)) * 100))
    }

    private var linkedAccounts: [Emails] {
        profiles.primary?.emails ?? []
    }

    private var filteredPasses: [PreloadedEmailPassItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return preloadedPasses }
        return preloadedPasses.filter { matches($0.pass, query: query) }
    }

    private var groupedPassSections: [(title: String, items: [PreloadedEmailPassItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredPasses) { item -> Date in
            let comps = calendar.dateComponents([.year], from: item.pass.startDate)
            return calendar.date(from: comps) ?? item.pass.startDate
        }

        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { lhs, rhs in
                if lhs.pass.startDate != rhs.pass.startDate {
                    return lhs.pass.startDate > rhs.pass.startDate
                }
                return lhs.pass.endDate > rhs.pass.endDate
            }
            return (yearSectionTitle(for: key), items)
        }
    }

    private var progressLabel: String {
        guard let progress = syncProgress else {
            return String(localized: "Connecting…")
        }
        switch progress.stage {
        case .searching:
            return String(localized: "Searching…")
        case .downloading:
            return String(localized: "Fetching \(globalPercentage)%")
        case .finished:
            return String(localized: "Scan complete")
        }
    }

    private var progressSublabel: String {
        guard let progress = syncProgress else {
            return String(localized: "This can take a moment on the first scan.")
        }
        switch progress.stage {
        case .searching:
            return ""
        case .downloading:
            return ""
        case .finished:
            return ""
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
                if linkedAccounts.isEmpty {
                    ContentUnavailableView(
                        "No email linked",
                        systemImage: "bell.slash",
                        description: Text("Add an email account in Profile → Email to import Trenitalia passes.")
                    )
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                } else if isWorking && preloadedPasses.isEmpty {
                    progressView
                } else if preloadedPasses.isEmpty {
                    ContentUnavailableView {
                        Label("No passes found", systemImage: "envelope")
                    } description: {
                        if let syncError {
                            Text(syncError)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("No Trenitalia Abbonamento emails with PDF attachments were found.")
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
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredPasses.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(Color.secondary)
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

                        ForEach(groupedPassSections, id: \.title) { section in
                            Section {
                                ForEach(section.items) { item in
                                    passRow(item)
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

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticFeedback.select()
                        showSaveAllConfirmation = true
                    } label: {
                        Text("Save all")
                    }
                    .disabled(isWorking || filteredPasses.isEmpty)
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .confirmationDialog("Save all passes", isPresented: $showSaveAllConfirmation, titleVisibility: .visible) {
                Button("Cancel", role: .cancel) { }
                Button("Save", role: .none) { saveAllPasses() }
            } message: {
                Text("Are you sure you want to save all fetched passes?")
            }
        .searchable(text: $searchText, prompt: "Search")
        .background(appBackgroundColor.ignoresSafeArea())
        .presentationBackground(appBackgroundColor)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            if autoScanOnAppear {
                beginScan(reloadAll: false)
            } else {
                reloadPassesFromProfile()
            }
        }
        .onDisappear { syncTask?.cancel() }
    }

    // MARK: - Subviews

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

    @ViewBuilder
    private func passRow(_ item: PreloadedEmailPassItem) -> some View {
        let isAdded = isAlreadyAdded(item.pass)
        let canAdd = !isAdded && !item.pass.qrcode.isEmpty

        Button {
            addPass(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let image = UIImage(data: item.pass.qrcode) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .padding(4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(PassValidityPeriod.text(
                        name: item.pass.name,
                        start: item.pass.startDate,
                        end: item.pass.endDate
                    ))
                    .font(.headline)
                    Text(item.pass.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !item.pass.price.isEmpty {
                    Text(item.pass.price)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .fontDesign(appFontDesign)
    }

    // MARK: - Actions

    private func matches(_ pass: EmailPassContent, query: String) -> Bool {
        if pass.name.lowercased().contains(query) { return true }

        let dates = [
            pass.startDate.formatted(.dateTime.day().month().year()),
            pass.startDate.formatted(date: .abbreviated, time: .omitted),
            pass.startDate.formatted(date: .numeric, time: .omitted),
            pass.endDate.formatted(.dateTime.day().month().year()),
            pass.endDate.formatted(date: .abbreviated, time: .omitted),
            pass.endDate.formatted(date: .long, time: .omitted),
            pass.endDate.formatted(date: .numeric, time: .omitted),
            pass.endDate.formatted(.dateTime.month(.wide)),
            pass.endDate.formatted(.dateTime.year())
        ]
        return dates.contains { $0.lowercased().contains(query) }
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
        defer { isWorking = false }
        syncError = nil
        syncProgress = nil
        accountProgresses = []
        var errors: [String] = []

        let configuredAccounts = profile.emails.filter(\.hasConfiguredCredentials)
        accountProgresses = configuredAccounts.map {
            AccountSyncProgress(email: $0.email, found: 0, processed: 0)
        }

        for (accountIndex, account) in configuredAccounts.enumerated() {
            guard !Task.isCancelled else { return }
            do {
                let result = try await EmailPassSyncService.syncAccount(
                    accountID: account.id,
                    profile: profile,
                    modelContext: modelContext,
                    reloadAll: reloadAll
                ) { progress in
                    syncProgress = progress
                    if progress.stage == .downloading {
                        accountProgresses[accountIndex].found = progress.emailsFound
                        accountProgresses[accountIndex].processed = progress.emailsDownloaded
                    }
                    if let warning = progress.latestWarning {
                        syncError = warning
                    }
                }
                accountProgresses[accountIndex].processed = accountProgresses[accountIndex].found
                errors.append(contentsOf: result.warnings.map { "\(account.email): \($0)" })
            } catch {
                errors.append("\(account.email): \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }
        if !errors.isEmpty {
            syncError = errors.joined(separator: "\n")
        }
        reloadPassesFromProfile()
    }

    @MainActor
    private func reloadPassesFromProfile() {
        guard let profile = profiles.primary else { return }
        preloadedPasses = EmailPassSyncService.passes(from: profile).map { account, pass in
            PreloadedEmailPassItem(id: pass.id, pass: pass, accountEmail: account.email)
        }
    }

    private func addPass(_ item: PreloadedEmailPassItem) {
        guard !isAlreadyAdded(item.pass) else { return }
        HapticFeedback.confirm()
        // already on the main actor; the Task only crossed a concurrency
        // boundary with non-Sendable models for no benefit
        EmailPassSyncService.savePass(item.pass, modelContext: modelContext, existingPasses: passes)
        onPassAdded?()
        dismiss()
    }

    private func saveAllPasses() {
        HapticFeedback.success()
        var addedCount = 0
        var newlyAdded: [Pass] = []
        for item in filteredPasses where !item.pass.qrcode.isEmpty {
            let alreadyStored = isAlreadyAdded(item.pass, newlyAdded: newlyAdded)
            // savePass updates an existing record in place and attaches the PDF,
            // so it handles both the new and the already-imported case
            if let saved = EmailPassSyncService.savePass(
                item.pass,
                modelContext: modelContext,
                existingPasses: passes + newlyAdded
            ), !alreadyStored {
                newlyAdded.append(saved)
                addedCount += 1
            }
        }
        
        if addedCount > 0 {
            try? modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
            onPassAdded?()
            dismiss()
        }
    }

    private func isAlreadyAdded(_ emailPass: EmailPassContent, newlyAdded: [Pass] = []) -> Bool {
        let allPasses = passes + newlyAdded
        return allPasses.contains {
            Calendar.current.isDate($0.start_date, inSameDayAs: emailPass.startDate)
                && Calendar.current.isDate($0.expiry_date, inSameDayAs: emailPass.endDate)
                && $0.name.caseInsensitiveCompare(emailPass.name) == .orderedSame
        }
    }
}

private struct EmailPassImportPreview: View {
    // MARK: - Properties

    let container: ModelContainer

    // MARK: - Body

    var body: some View {
        NavigationStack {
            EmailPassImportView(autoScanOnAppear: false)
                .modelContainer(container)
        }
    }
}

#Preview("Email Pass Import View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self,
        configurations: config
    )

    let emailAccount = Emails(
        provider: .apple,
        email: "preview@icloud.com",
        appPassword: "preview-password"
    )
    container.mainContext.insert(UserProfile(name: "Francesco", emails: [emailAccount]))

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            EmailPassImportPreview(container: container)
        }
}
