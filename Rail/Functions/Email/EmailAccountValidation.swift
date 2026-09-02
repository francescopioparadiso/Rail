import Foundation

/// Returns the profile's configured mailboxes whose credentials still authenticate,
/// in profile order. Every account is probed concurrently, so the wait is the slowest
/// mailbox rather than their sum, and failures are simply dropped.
@MainActor
func validatedEmailAccounts(from profile: UserProfile) async -> [Emails] {
    let configured = profile.emails.filter(\.hasConfiguredCredentials)
    return await withTaskGroup(of: (offset: Int, account: Emails)?.self) { group in
        for (offset, account) in configured.enumerated() {
            group.addTask {
                guard !Task.isCancelled else { return nil }
                do {
                    try await EmailTrainFetcher(account: account).verifyCredentials()
                    return (offset, account)
                } catch {
                    return nil
                }
            }
        }

        var validated: [(offset: Int, account: Emails)] = []
        for await result in group {
            if let result { validated.append(result) }
        }
        return validated.sorted { $0.offset < $1.offset }.map(\.account)
    }
}
