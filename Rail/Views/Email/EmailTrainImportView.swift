import SwiftUI
import SwiftData

// MARK: - Secondary Views

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
    @Query private var profiles: [UserProfile]
    @Query private var trains: [Train]

    var onTrainAdded: (() -> Void)? = nil

    @State private var preloadedTickets: [PreloadedEmailTicketItem] = []
    @State private var preparedTrains: [UUID: PreparedEmailTrain] = [:]
    @State private var isWorking = false
    @State private var isPreparing = false
    @State private var hasStarted = false
    @State private var syncError: String?
    @State private var syncProgress: EmailTicketSyncProgress?
    @State private var preparedCount = 0
    @State private var preparationTotal = 0
    @State private var syncTask: Task<Void, Never>?

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
                    .fontDesign(app_font_design)
                } else if isWorking && preloadedTickets.isEmpty {
                    progressView
                } else if preloadedTickets.isEmpty {
                    ContentUnavailableView {
                        Label("No tickets found", systemImage: "envelope")
                            .font(.subheadline)
                    } description: {
                        if let syncError {
                            Text(syncError)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("No Trenitalia self-check-in emails were found for your linked accounts.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                    } actions: {
                        Button {
                            beginScan()
                        } label: {
                            Label("Scan Mailbox", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .disabled(isWorking)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .refreshable {
                        await refreshMailbox()
                    }
                    .foregroundStyle(.secondary)
                    .fontDesign(app_font_design)
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

                        Section {
                            ForEach(preloadedTickets) { item in
                                ticketRow(item)
                            }
                        } header: {
                            Text("\(preloadedTickets.count) \(preloadedTickets.count == 1 ? "ticket" : "tickets")")
                        } footer: {
                            Text("Tap a ticket to add it to Today.")
                        }
                        .fontDesign(app_font_design)
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await refreshMailbox()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app_background_color)
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
            }
        }
        .background(app_background_color.ignoresSafeArea())
        .presentationBackground(app_background_color)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            beginScan()
        }
        .onDisappear { syncTask?.cancel() }
    }

    // MARK: - Computed Properties
    private var linkedAccounts: [Emails] {
        profiles.first?.emails ?? []
    }

    // MARK: - Secondary Views
    @ViewBuilder
    private var progressView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(progressTitle)
                .font(.headline)

            Text(progressDetails)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .fontDesign(app_font_design)
        .padding()
    }

    private var progressTitle: String {
        if isPreparing {
            return String(localized: "Preparing trains…")
        }
        switch syncProgress?.stage {
        case .searching:
            return String(localized: "Searching your inbox…")
        case .downloading:
            return String(localized: "Reading ticket emails…")
        case .fetchingDetails:
            return String(localized: "Fetching passenger and QR details…")
        case .finished:
            return String(localized: "Finishing the scan…")
        case nil:
            return String(localized: "Connecting to your inbox…")
        }
    }

    private var progressDetails: String {
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
            return progress.accountEmail
        case .downloading:
            if progress.emailsSkipped > 0 {
                return String(
                    localized: "Processed \(progress.emailsDownloaded) of \(progress.emailsFound) emails · Skipped \(progress.emailsSkipped)"
                )
            }
            return String(localized: "Processed \(progress.emailsDownloaded) of \(progress.emailsFound) emails")
        case .fetchingDetails:
            return String(
                localized: "Processed \(progress.emailsDownloaded) emails · Details \(progress.detailsCompleted) of \(progress.detailsTotal)"
            )
        case .finished:
            return String(localized: "Found \(progress.emailsFound) new emails")
        }
    }

    // MARK: - Functions
    private func beginScan() {
        guard !isWorking else { return }
        syncTask = Task {
            await scanMailbox()
        }
    }

    private func refreshMailbox() async {
        if isWorking, let syncTask {
            await syncTask.value
            return
        }
        let task = Task {
            await scanMailbox()
        }
        syncTask = task
        await task.value
    }

    @MainActor
    private func scanMailbox() async {
        guard let profile = profiles.first else { return }

        isWorking = true
        defer {
            isPreparing = false
            isWorking = false
        }
        isPreparing = false
        syncError = nil
        syncProgress = nil
        preparedCount = 0
        preparationTotal = 0
        var errors: [String] = []

        for account in profile.emails {
            guard !Task.isCancelled else { return }
            do {
                let result = try await EmailTicketSyncService.syncAccount(
                    accountID: account.id,
                    profile: profile,
                    modelContext: modelContext
                ) { progress in
                    syncProgress = progress
                    if let warning = progress.latestWarning {
                        syncError = warning
                    }
                }
                errors.append(contentsOf: result.warnings.map { "\(account.email): \($0)" })
            } catch {
                errors.append("\(account.email): \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }
        if !errors.isEmpty {
            syncError = errors.joined(separator: "\n")
        }
        await reloadTicketsFromProfile()
    }

    @MainActor
    private func reloadTicketsFromProfile() async {
        guard let profile = profiles.first else { return }

        let tickets = EmailTicketSyncService.tickets(from: profile)
        preloadedTickets = tickets.map { account, ticket in
            PreloadedEmailTicketItem(
                id: ticket.id,
                ticket: ticket,
                accountEmail: account.email,
                state: ticket.isImportEligible && ticket.hasLoadedDetails ? .loading : .unavailable
            )
        }
        preparedTrains = [:]

        let ticketsToPrepare = tickets.filter {
            $0.ticket.isImportEligible
                && $0.ticket.hasLoadedDetails
                && !isAlreadyAdded($0.ticket.id)
        }
        isPreparing = !ticketsToPrepare.isEmpty
        preparationTotal = ticketsToPrepare.count
        preparedCount = 0

        for item in ticketsToPrepare {
            guard !Task.isCancelled else { return }
            let ticket = item.ticket
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

    @ViewBuilder
    private func ticketRow(_ item: PreloadedEmailTicketItem) -> some View {
        let isPast = item.ticket.isPastDeparture
        let isAdded = isAlreadyAdded(item.id)
        let canAdd = item.state == .ready && item.ticket.isImportEligible && !isAdded

        Button {
            addTicket(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                EmailTicketRow(ticket: item.ticket)
                    .overlay(alignment: .trailing) {
                        if isPast {
                            statusLabel("Departed", systemImage: "clock.fill", color: .secondary)
                        } else if isAdded {
                            statusLabel("Added", systemImage: "checkmark.circle.fill", color: .green)
                        } else if item.state == .loading {
                            ProgressView()
                                .padding(.trailing, 16)
                        } else if item.state == .unavailable {
                            statusLabel("Unavailable", systemImage: "exclamationmark.triangle.fill", color: .orange)
                        }
                    }

                if !isPast, !isAdded, item.state == .unavailable {
                    Text(
                        item.ticket.detailsError
                            ?? String(localized: "This train could not be prepared from the ticket details.")
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .opacity(canAdd ? 1 : 0.55)
    }

    private func statusLabel(_ title: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)

            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.trailing, 8)
    }

    private func addTicket(_ item: PreloadedEmailTicketItem) {
        guard item.state == .ready,
              item.ticket.isImportEligible,
              !isAlreadyAdded(item.id),
              let prepared = preparedTrains[item.id] else { return }

        HapticFeedback.confirm()
        let passengers = resolvedPassengers(for: item.ticket, prepared: prepared)
        EmailTrainService.savePreparedTrain(
            PreparedEmailTrain(prepared: prepared.prepared, passengers: passengers),
            sourceTicketID: item.id,
            modelContext: modelContext,
            profile: profiles.first
        )
        onTrainAdded?()
        dismiss()
    }

    private func resolvedPassengers(
        for ticket: EmailContent,
        prepared: PreparedEmailTrain
    ) -> [EmailContentPassenger] {
        ticket.passengers.isEmpty ? prepared.passengers : ticket.passengers
    }

    private func isAlreadyAdded(_ ticketID: UUID) -> Bool {
        trains.contains { $0.sourceEmailTicketID == ticketID }
    }
}

// MARK: - Secondary Views

struct EmailTicketRow: View {
    let ticket: EmailContent

    private var displayDate: Date {
        ticket.departureDate ?? ticket.date
    }

    private var title: String {
        let destination = stationCity(ticket.arrivalStation)
        if destination.isEmpty {
            return ticket.trainNumber.isEmpty ? String(localized: "Ticket") : "Train \(ticket.trainNumber)"
        }
        return destination
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DepartureCalendarBadge(date: displayDate)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fontDesign(app_font_design)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let weekday = displayDate.formatted(.dateTime.weekday(.abbreviated))
        let time = displayDate.formatted(date: .omitted, time: .shortened)

        if ticket.departureStation.isEmpty {
            return "\(weekday) · \(time)"
        }

        return "\(ticket.departureStation) · \(weekday) · \(time)"
    }

    private func stationCity(_ station: String) -> String {
        station.split(separator: " ").first.map(String.init) ?? station
    }
}

struct DepartureCalendarBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)

            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 48)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}

// MARK: - Previews

private struct EmailTrainImportPreview: View {
    let container: ModelContainer

    var body: some View {
        EmailTrainImportView()
            .modelContainer(container)
    }
}

#Preview("Email Train Import View") {
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
            EmailTrainImportPreview(container: container)
        }
}
