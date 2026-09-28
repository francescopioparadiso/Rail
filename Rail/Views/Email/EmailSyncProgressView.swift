import SwiftUI

struct AccountSyncProgress: Identifiable, Equatable {
    let email: String
    var found: Int
    var processed: Int
    var id: String { email }
}

/// Shown above the list while mail that arrived since the last sync is fetched —
/// the full `EmailSyncProgressView` is kept for scans that read the whole mailbox.
struct EmailFetchingNewestIndicator: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .fontDesign(appFontDesign)
    }
}

struct EmailSyncProgressView: View {
    // MARK: - Properties

    let isFetching: Bool
    let progressTitle: String
    let globalPercentage: Double
    let accountProgresses: [AccountSyncProgress]
    let progressSublabel: String?
    let onRestart: () -> Void

    // MARK: - Body

    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 12) {
                Group {
                    if !isFetching {
                        Image(systemName: "envelope.badge")
                    } else {
                        Image(systemName: "progress.indicator")
                            .symbolEffect(.rotate)
                    }
                }
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                .font(.largeTitle)
                .foregroundStyle(.secondary)
    
                Text(progressTitle)
                    .font(.title2.bold())
                    .contentTransition(.numericText(value: globalPercentage))
    
                if !accountProgresses.isEmpty && isFetching {
                    VStack(spacing: 6) {
                        ForEach(accountProgresses) { account in
                            HStack {
                                Text(account.email)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(account.processed) of \(account.found)")
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(account.processed)))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
    
                if let progressSublabel, !progressSublabel.isEmpty {
                    Text(progressSublabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                }
            }
            .fontDesign(appFontDesign)
            .animation(.default, value: isFetching)
            .animation(.default, value: globalPercentage)
            .animation(.default, value: progressTitle)
            .animation(.default, value: accountProgresses)
            .padding()
            
            Spacer()
            
            Button {
                HapticFeedback.confirm()
                onRestart()
            } label: {
                Label("Scan again emails", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
        }
    }
}
