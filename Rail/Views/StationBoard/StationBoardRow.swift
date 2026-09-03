import SwiftUI
import UIKit

/// One line of a station board: when the train is due, what it is, and where it is
/// headed or coming from.
struct StationBoardRow: View {
    // MARK: - Properties

    let train: BoardTrain

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
            // the same yellow chip a platform wears everywhere else in the app. No
            // arrow on it here: a whole board is going the one way, so repeating it
            // on every row says nothing the picker above hasn't.
            Text(train.platform)
                .font(.subheadline).fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                // a floor so "3" and "12" make chips of a size, and no ceiling: a
                // platform like "1 Tronco" widens its own chip to fit rather than
                // being clipped, and the station name gives up the room
                .frame(minWidth: 18)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.yellow.opacity(0.5))
                .cornerRadius(16)
        }
    }
}
