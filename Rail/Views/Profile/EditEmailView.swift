import SwiftUI
import SwiftData

struct EditEmailView: View {
    // MARK: - Properties

    @Bindable var profile: UserProfile
    let accountID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var isPasswordVisible = false
    @State private var status: CredentialStatus = .checking
    @State private var verifyTask: Task<Void, Never>?

    // MARK: - Computed

    private var account: Emails? {
        profile.emails.first { $0.id == accountID }
    }

    private var showsCustomIMAPSettings: Bool {
        guard let account = account else { return false }
        guard account.provider == .other else { return false }
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let domain = email.split(separator: "@").last else { return false }
        return domain.contains(".")
    }

    private var showsCredentialStatus: Bool {
        guard let account = account else { return false }
        let password = account.appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return !password.isEmpty && canVerifyCredentials(for: account)
    }

    private var credentialCheckKey: String {
        guard let account = account else { return "" }
        return "\(account.email)|\(account.appPassword)|\(account.customIMAPServer ?? "")|\(account.customIMAPPort.map(String.init) ?? "")"
    }

    private var emailTextBinding: Binding<String> {
        Binding(
            get: { account?.email ?? "" },
            set: { newValue in
                updateAccount { account in
                    let provider = EmailProvider.inferred(from: newValue)
                    account.email = newValue
                    account.provider = provider
                    if provider == .other {
                        if account.customIMAPPort == nil {
                            account.customIMAPPort = 993
                        }
                    } else {
                        account.customIMAPServer = nil
                        account.customIMAPPort = nil
                    }
                }
            }
        )
    }

    private var passwordBinding: Binding<String> {
        Binding(
            get: { account?.appPassword ?? "" },
            set: { newValue in
                updateAccount { account in
                    account.appPassword = newValue
                }
            }
        )
    }

    private var customIMAPServerBinding: Binding<String> {
        Binding(
            get: { 
                guard let account = account else { return "" }
                return account.provider == .other ? (account.customIMAPServer ?? "") : account.provider.server
            },
            set: { newValue in
                updateAccount { account in
                    if account.provider == .other {
                        account.customIMAPServer = newValue
                    }
                }
            }
        )
    }

    private var customIMAPPortBinding: Binding<String> {
        Binding(
            get: {
                guard let account = account else { return "" }
                let port = account.provider == .other ? (account.customIMAPPort ?? 993) : account.provider.port
                return String(port)
            },
            set: { newValue in
                updateAccount { account in
                    if account.provider == .other {
                        let digits = newValue.filter(\.isNumber)
                        account.customIMAPPort = Int(digits).flatMap { (1...65535).contains($0) ? $0 : nil } ?? 993
                    }
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Form {
            if let account = account {
                Section {
                    TextField("Email Address", text: emailTextBinding)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        
                    HStack(spacing: 10) {
                        Group {
                            if isPasswordVisible {
                                TextField("App Password", text: passwordBinding)
                            } else {
                                SecureField("App Password", text: passwordBinding)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        
                        if !account.appPassword.isEmpty {
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isPasswordVisible ? "Hide app password" : "Show app password")
                        } else if let link = account.provider.linkDestination {
                            Button {
                                openURL(link)
                            } label: {
                                Text("Generate")
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                } header: {
                    Text("Email Credentials")
                } footer: {
                    if showsCredentialStatus {
                        Text(status.text)
                            .foregroundStyle(status.foregroundColor)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: status)
                    }
                }
                
                Section {
                    TextField("IMAP Server", text: customIMAPServerBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(account.provider != .other)
                        .foregroundStyle(account.provider != .other ? .secondary : .primary)

                    TextField("Port", text: customIMAPPortBinding)
                        .keyboardType(.numberPad)
                        .disabled(account.provider != .other)
                        .foregroundStyle(account.provider != .other ? .secondary : .primary)
                } header: {
                    Text("IMAP Settings")
                } footer: {
                    if account.provider == .other {
                        if showsCustomIMAPSettings {
                            Text("This email domain isn’t recognized. Enter your provider’s IMAP server and port.")
                        }
                    }
                }
            } else {
                Text("Account not found")
            }
        }
        // keeps the standard grouped background so the sections stay legible in
        // dark mode, where `appBackgroundColor` matches the row fill
        .background(appBackgroundColor.ignoresSafeArea())
        .navigationTitle(account?.email.isEmpty == false ? account!.email : String(localized: "Email Details"))
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .onAppear {
            scheduleCredentialVerification()
        }
        .onChange(of: credentialCheckKey) { _, _ in
            scheduleCredentialVerification()
        }
        .onDisappear {
            verifyTask?.cancel()
        }
    }

    // MARK: - Actions

    private func canVerifyCredentials(for account: Emails) -> Bool {
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = account.appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty, email.contains("@") else { return false }
        if account.provider == .other {
            return !account.imapServer.isEmpty
        }
        return true
    }

    @MainActor
    private func scheduleCredentialVerification() {
        verifyTask?.cancel()
        verifyTask = Task {
            await verifyCredentials()
        }
    }

    @MainActor
    private func verifyCredentials() async {
        guard let account = account, canVerifyCredentials(for: account) else {
            return
        }

        status = .checking

        do {
            try await EmailTrainFetcher(account: account).verifyCredentials()
            guard !Task.isCancelled else { return }
            status = .valid
        } catch {
            guard !Task.isCancelled else { return }
            status = .invalid
        }
    }

    private func updateAccount(_ mutate: (inout Emails) -> Void) {
        var emails = profile.emails
        guard let index = emails.firstIndex(where: { $0.id == accountID }) else { return }
        mutate(&emails[index])
        profile.emails = emails
        try? modelContext.save()
    }
}

private enum CredentialStatus: Equatable {
    case checking
    case valid
    case invalid

    var text: String {
        switch self {
        case .checking:
            return String(localized: "Checking validity…")
        case .valid:
            return String(localized: "Valid credentials")
        case .invalid:
            return String(localized: "Invalid credentials")
        }
    }

    var foregroundColor: Color {
        switch self {
        case .checking:
            return .secondary
        case .valid:
            return .green
        case .invalid:
            return .red
        }
    }
}
