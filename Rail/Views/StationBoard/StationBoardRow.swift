import SwiftUI
import UIKit

/// One line of a station board: when the train is due, what it is, and where it is
/// headed or coming from.
struct StationBoardRow: View {
    // MARK: - Properties

    let train: BoardTrain
    let kind: StationBoardKind

    // MARK: - Computed

    /// Trenitalia prints categories the app has no badge for. Rather than leave a
    /// blank where the logo goes, those fall back to the acronym itself.
    private var hasLogoImage: Bool {
        !train.logo.isEmpty && UIImage(named: train.logo) != nil
    }

    /// One colour for the whole row's time: red once the train is losing time,
    /// green while it is not. It applies to a train still sitting at its origin
    /// just as much as to one already running.
    private var timeColor: Color {
        train.delayMinutes > 0 ? .red : .green
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 20) {
            time

            // the station is what you scan a board for; the train that serves it
            // is the detail underneath
            VStack(alignment: .leading, spacing: 4) {
                Text(train.counterpart)
                    .font(.headline).fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    logo
                    Text(train.number)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            platform
        }
        .fontDesign(appFontDesign)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    /// When the train is actually expected, and nothing else — the colour already
    /// says whether that is late, so printing the booked time beside it only ever
    /// repeated the same fact twice.
    private var time: some View {
        Text(train.effectiveTime, format: .dateTime.hour().minute())
            .font(.title3).fontWeight(.semibold)
            .monospacedDigit()
            .strikethrough(train.isCancelled, color: .red)
            .foregroundStyle(train.isCancelled ? Color.red : timeColor)
            .frame(width: 58, alignment: .leading)
    }

    @ViewBuilder
    private var logo: some View {
        if hasLogoImage {
            Image(train.logo)
                .resizable()
                .scaledToFit()
                .frame(height: UIFont.preferredFont(forTextStyle: .subheadline).lineHeight * 0.9)
        } else if !train.logo.isEmpty {
            Text(train.logo)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var platform: some View {
        if !train.platform.isEmpty, train.platform != "-" {
            // the same yellow chip a platform wears everywhere else in the app,
            // with the arrow that says which way the train is going through here
            HStack(spacing: 4) {
                Image(systemName: kind == .departures ? "arrow.up.right" : "arrow.down.right")

                // a minimum width so "3" and "12" make chips of the same size,
                // while a platform like "1 /" still gets the room it needs
                Text(train.platform)
                    .monospacedDigit()
                    .frame(minWidth: 18)
            }
            .font(.subheadline).fontWeight(.medium)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.yellow.opacity(0.5))
            .cornerRadius(16)
        }
    }
}
