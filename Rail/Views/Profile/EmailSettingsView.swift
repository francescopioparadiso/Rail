import SwiftUI
import SwiftData

struct EmailSettingsView: View {
    // MARK: - Properties

    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var searchText = ""
    @State private var showAddEmailSheet = false

    // MARK: - Computed

    private var filteredAccounts: [Emails] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return profile.emails }
        return profile.emails.filter {
            $0.email.lowercased().contains(query)
                || $0.provider.rawValue.lowercased().contains(query)
        }
    }

    private var activeAccounts: [Emails] { filteredAccounts.filter(\.isEnabled) }
    private var inactiveAccounts: [Emails] { filteredAccounts.filter { !$0.isEnabled } }

    // MARK: - Body

    var body: some View {
        Group {
            if filteredAccounts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No email accounts" : "No Results",
                    systemImage: searchText.isEmpty ? "envelope.badge.plus" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Tap + to add an email account for ticket and pass import."
                            : "No email accounts match “\(searchText)”."
                    )
                )
                .foregroundStyle(.secondary)
                .fontDesign(appFontDesign)
            } else {
                List {
                    // one plain section until an account is disabled
                    if inactiveAccounts.isEmpty {
                        Section {
                            rows(for: activeAccounts)
                        }
                    } else {
                        if !activeAccounts.isEmpty {
                            Section("Active Emails") {
                                rows(for: activeAccounts)
                            }
                        }
                        Section("Inactive Emails") {
                            rows(for: inactiveAccounts)
                        }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .listStyle(.insetGrouped)
                // the standard grouped background: `appBackgroundColor` matches the
                // row fill in dark mode, which left the rows invisible
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .navigationTitle("Email")
        .fontDesign(appFontDesign)
        .searchable(text: $searchText, prompt: "Search")
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)

            // fixed, not flexible, so the search field grows up to the plus button
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    HapticFeedback.confirm()
                    showAddEmailSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddEmailSheet) {
            AddEmailSheetView(profile: profile)
        }
        .onAppear {
            if profile.emails.isEmpty {
                showAddEmailSheet = true
            }
        }
        .onDisappear {
            pruneEmptyAccounts()
        }
    }

    private func rows(for accounts: [Emails]) -> some View {
        ForEach(accounts) { account in
            NavigationLink {
                EditEmailView(profile: profile, accountID: account.id)
            } label: {
                Text(account.email.isEmpty ? String(localized: "New Email") : account.email)
                    .foregroundStyle(account.isEnabled ? .primary : .secondary)
            }
        }
        .onDelete { offsets in
            let ids = Set(offsets.map { accounts[$0].id })
            deleteAccounts(withIDs: ids)
        }
    }

    // MARK: - Actions

    private func deleteAccounts(withIDs ids: Set<UUID>) {
        profile.emails.removeAll { ids.contains($0.id) }
        try? modelContext.save()
    }

    private func pruneEmptyAccounts() {
        let trimmed = profile.emails.filter {
            !($0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        guard trimmed.count != profile.emails.count else { return }
        profile.emails = trimmed
        try? modelContext.save()
    }
}

#Preview("Email View - Populated List") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self, configurations: config)
    let profile = UserProfile(name: "Francesco", emails: [
        Emails(provider: .apple, email: PreviewCredentials.appleEmail, appPassword: PreviewCredentials.appleAppPassword),
        Emails(provider: .google, email: "test.account@gmail.com", appPassword: "somepassword"),
        Emails(provider: .other, email: "user@customdomain.com", appPassword: "password", customIMAPServer: "imap.custom.com", customIMAPPort: 993)
    ])
    container.mainContext.insert(profile)

    return NavigationStack {
        EmailSettingsView(profile: profile)
            .modelContainer(container)
    }
}
