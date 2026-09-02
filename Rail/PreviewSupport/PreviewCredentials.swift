import Foundation

/// Real mailboxes for SwiftUI previews that hit IMAP for real.
///
/// Values live in `.env.local` at the repo root, which is gitignored — nothing
/// secret is committed. Accounts are numbered pairs:
///
///     email1=someone@icloud.com
///     password1=xxxx-xxxx-xxxx-xxxx
///     email2=someone@gmail.com
///     password2=xxxx-xxxx-xxxx-xxxx
///
/// The IMAP host and port are never written down: they're derived from the
/// address domain through `EmailProvider`, the same mapping the app itself uses.
///
/// `#filePath` resolves the file on the machine that compiled the code, so
/// previews work locally and fall back to harmless placeholders anywhere else.
/// `#Preview` bodies are compiled into release builds too, so this type must
/// always exist — only the lookup is debug-only.
enum PreviewCredentials {
    struct Account {
        let email: String
        let appPassword: String

        var provider: EmailProvider { EmailProvider.inferred(from: email) }
        /// nil when the domain isn't one the app knows how to reach.
        var server: String? { provider == .other ? nil : provider.server }
        var port: Int { provider.port }
    }

    /// Every configured mailbox, in file order.
    static var accounts: [Account] {
        #if DEBUG
        var found: [Account] = []
        var index = 1
        while let email = values["email\(index)"], !email.isEmpty {
            found.append(Account(email: email, appPassword: values["password\(index)"] ?? ""))
            index += 1
        }
        return found
        #else
        return []
        #endif
    }

    static func account(for provider: EmailProvider) -> Account? {
        accounts.first { $0.provider == provider }
    }

    // Conveniences for the previews, falling back when nothing is configured.
    static var appleEmail: String { account(for: .apple)?.email ?? "preview@icloud.com" }
    static var appleAppPassword: String { nonEmpty(account(for: .apple)?.appPassword) }
    static var googleEmail: String { account(for: .google)?.email ?? "preview@gmail.com" }
    static var googleAppPassword: String { nonEmpty(account(for: .google)?.appPassword) }

    private static func nonEmpty(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "preview-password" }
        return value
    }

    #if DEBUG
    private static let values: [String: String] = {
        guard let url = envURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return text.split(separator: "\n").reduce(into: [:]) { result, line in
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.hasPrefix("#"), let separator = entry.firstIndex(of: "=") else { return }
            let key = entry[..<separator].trimmingCharacters(in: .whitespaces)
            let value = entry[entry.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }()

    /// Walks up from this source file until it finds the directory holding `.env.local`.
    private static var envURL: URL? {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appending(path: ".env.local")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
    #endif
}
