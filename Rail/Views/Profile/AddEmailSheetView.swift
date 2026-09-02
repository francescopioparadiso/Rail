import SwiftUI
import SwiftData

struct AddEmailSheetView: View {
    // MARK: - Properties

    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var appPassword = ""
    @State private var isPasswordVisible = false
    @State private var customIMAPServer = ""
    @State private var customIMAPPort = ""
    @FocusState private var isEmailFocused: Bool

    // MARK: - Computed

    private var provider: EmailProvider {
        EmailProvider.inferred(from: email)
    }

    private var showsCustomIMAPSettings: Bool {
        guard provider == .other else { return false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let domain = trimmed.split(separator: "@").last else { return false }
        return domain.contains(".")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email Address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEmailFocused)
                        
                    HStack(spacing: 10) {
                        Group {
                            if isPasswordVisible {
                                TextField("App Password", text: $appPassword)
                            } else {
                                SecureField("App Password", text: $appPassword)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        
                        if !appPassword.isEmpty {
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isPasswordVisible ? "Hide app password" : "Show app password")
                        } else if let link = provider.linkDestination {
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
                }
                
                Section {
                    TextField("IMAP Server", text: $customIMAPServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(provider != .other)
                        .foregroundStyle(provider != .other ? .secondary : .primary)

                    TextField("Port", text: $customIMAPPort)
                        .keyboardType(.numberPad)
                        .disabled(provider != .other)
                        .foregroundStyle(provider != .other ? .secondary : .primary)
                } header: {
                    Text("IMAP Settings")
                } footer: {
                    if provider == .other {
                        if showsCustomIMAPSettings {
                            Text("This email domain isn’t recognized. Enter your provider’s IMAP server and port.")
                        }
                    }
                }
            }
            .navigationTitle("Add Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveEmail()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(
                        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .fontDesign(.rounded)
            .onAppear {
                isEmailFocused = true
            }
            .onChange(of: provider) { _, newProvider in
                if newProvider == .other {
                    customIMAPServer = ""
                    customIMAPPort = ""
                } else {
                    customIMAPServer = newProvider.server
                    customIMAPPort = String(newProvider.port)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func saveEmail() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let portInt = Int(customIMAPPort.filter(\.isNumber)).flatMap { (1...65535).contains($0) ? $0 : nil } ?? 993
        let trimmedServer = customIMAPServer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newAccount = Emails(
            provider: provider,
            email: trimmedEmail,
            appPassword: trimmedPassword,
            customIMAPServer: provider == .other ? trimmedServer : nil,
            customIMAPPort: provider == .other ? portInt : nil
        )
        
        profile.emails.append(newAccount)
        try? modelContext.save()
        dismiss()
    }
}
