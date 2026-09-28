import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

// A journey on the Lock Screen, in the Dynamic Island and on the Apple Watch's Smart
// Stack. One view per presentation, each with its own sizes at the top:
//
//   TrainActivityLockScreen      the Lock Screen (and, through it, the Watch)
//   TrainActivityWatch           the Watch's Smart Stack
//   TrainActivityIslandExpanded  the island, long-pressed open
//   TrainActivityIslandCompact   the island, closed, on its own
//   TrainActivityIslandMinimal   the island, sharing its space with another activity
//
// Below them, the few pieces they share, then the previews.
//
// What the activity carries, and the rules that decide it, are in `TrainActivity.swift`.

typealias TrainActivityContext = ActivityViewContext<TrainActivityAttributes>

// MARK: - Configuration

struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            TrainActivityLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // The top row, beside the camera, is kept by the island whether it is
                // used or not, so the header and seat go there and the bottom region
                // is left the stations and the chips.
                DynamicIslandExpandedRegion(.leading) {
                    TrainActivityIslandExpanded(context: context, region: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrainActivityIslandExpanded(context: context, region: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TrainActivityIslandExpanded(context: context, region: .bottom)
                }
            } compactLeading: {
                TrainActivityIslandCompact(context: context, side: .leading)
            } compactTrailing: {
                TrainActivityIslandCompact(context: context, side: .trailing)
            } minimal: {
                TrainActivityIslandMinimal(context: context)
            }
            .widgetURL(TrainActivityLinks.journey(context.attributes))
            .keylineTint(JourneyPalette.target)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Lock Screen

/// The journey in three bands: which train and which seat, the two ends of the leg,
/// and what is left to wait.
///
/// The system asks for this view on the Apple Watch's Smart Stack too, as the small
/// family, where it hands over to `TrainActivityWatch`.
struct TrainActivityLockScreen: View {
    let context: TrainActivityContext

    @Environment(\.activityFamily) private var family

    // The card's corner is rounded a good deal more than a chip's, so the chips sit
    // close to the edge; the text is set in a little further to line up with the
    // chips' own text.
    private let horizontalInset: CGFloat = 8
    private let verticalInset: CGFloat = 12
    private let textInset: CGFloat = 4
    private let bandSpacing: CGFloat = 10

    private let logoHeight: CGFloat = 22
    private let numberFont: Font = .title3
    private let stationFont: Font = .subheadline
    private let chipFont: Font = .subheadline

    var body: some View {
        Group {
            if family == .small {
                TrainActivityWatch(context: context)
            } else {
                card
                    // Low enough to keep the wallpaper showing through, which is what
                    // makes the whole thing read as glass rather than as a card.
                    .activityBackgroundTint(Color.black.opacity(0.12))
                    .activitySystemActionForegroundColor(JourneyPalette.target)
            }
        }
        .widgetURL(TrainActivityLinks.journey(context.attributes))
    }

    private var card: some View {
        let state = context.state
        // Passing the stop it was counting to moves the chips on to the next one, with
        // no update from the app; see `ContentState.advanced(ifStale:)`.
        let drawn = state.advanced(ifStale: context.isStale)

        return VStack(spacing: bandSpacing) {
            // Header: the train, and the seat — a tap on which opens the ticket.
            HStack(alignment: .center, spacing: 8) {
                TrainLogo(logo: context.attributes.logo, height: logoHeight)
                    .padding(.leading, textInset)

                Text(context.attributes.number)
                    .font(numberFont).fontWeight(.semibold).fontDesign(widgetFontDesign)
                    .foregroundStyle(Color.primary)

                Spacer()

                if let ticket = state.ticket, !ticket.label.trimmingCharacters(in: .whitespaces).isEmpty,
                   let link = TrainActivityLinks.seat(context.attributes, ticket) {
                    Link(destination: link) {
                        JourneyChip(font: chipFont) {
                            HStack(spacing: 4) {
                                Image(systemName: "carseat.left.fill")
                                Text(ticket.label)
                            }
                        }
                    }
                }
            }
            .padding(.top, -4)

            // Stations
            VStack(alignment: .leading, spacing: 4) {
                StationRow(row: state.departure, isCancelled: state.isCancelled)
                StationRow(row: state.arrival, isCancelled: state.isCancelled)
            }
            .font(stationFont)
            .padding(.horizontal, textInset)

            // Footer: where next and how long, and which platform.
            HStack(spacing: 8) {
                JourneyChip(
                    background: JourneyPalette.targetBackground,
                    foreground: JourneyPalette.target,
                    font: chipFont,
                    fillsWidth: true
                ) {
                    TargetLabel(name: drawn.state.targetName, date: drawn.state.targetDate, isStale: drawn.isStale)
                }

                if !Platform.isMissing(drawn.state.platform) {
                    JourneyChip(background: JourneyPalette.platformBackground, font: chipFont) {
                        PlatformLabel(platform: drawn.state.platform, isDeparture: drawn.state.isBoardingPlatform)
                    }
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .padding(.bottom, -4)
    }
}

// MARK: - Apple Watch

/// The journey on the Smart Stack, laid out like the expanded island: the train and
/// the seat, the two ends of the leg, then where next and which platform — all of
/// it, at sizes small enough for the card.
///
/// There is no preview: Xcode has no canvas for the `.small` family, so this is
/// checked on a watch.
struct TrainActivityWatch: View {
    let context: TrainActivityContext

    // How far the content is set in: the system leaves the sides some room already,
    // but nothing above the header or below the chips.
    private let horizontalInset: CGFloat = 4
    private let verticalInset: CGFloat = 9
    /// Between the header, the stations and the chips.
    private let bandSpacing: CGFloat = 4
    private let stationSpacing: CGFloat = 1
    /// The logo and the station rows sit a little further in than the chips, so
    /// their text lines up with the chips' own.
    private let textInset: CGFloat = 4

    private let logoHeight: CGFloat = 12
    private let numberFont: Font = .footnote
    /// Below the smallest text style, which is why it is a fixed size: the rows
    /// only need to be legible, the chips are what is read at a glance.
    private let stationFont: Font = .system(size: 11)
    private let chipFont: Font = .caption2
    private let chipVerticalPadding: CGFloat = 3
    private let chipHorizontalPadding: CGFloat = 6
    private let seatVerticalPadding: CGFloat = 2
    private let seatHorizontalPadding: CGFloat = 6

    var body: some View {
        let state = context.state
        let drawn = state.advanced(ifStale: context.isStale)

        return VStack(alignment: .leading, spacing: bandSpacing) {
            // Header: the train, and the seat.
            HStack(alignment: .center, spacing: 4) {
                TrainLogo(logo: context.attributes.logo, height: logoHeight)
                    .padding(.leading, textInset)

                Text(context.attributes.number)
                    .font(numberFont).fontWeight(.semibold).fontDesign(widgetFontDesign)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let ticket = state.ticket, !ticket.label.trimmingCharacters(in: .whitespaces).isEmpty {
                    JourneyChip(
                        background: JourneyPalette.seatBackground,
                        font: chipFont,
                        verticalPadding: seatVerticalPadding,
                        horizontalPadding: seatHorizontalPadding,
                        cornerRadius: 100
                    ) {
                        HStack(spacing: 2) {
                            Image(systemName: "figure.seated.seatbelt")
                            Text(ticket.label)
                        }
                    }
                }
            }

            // Stations
            VStack(alignment: .leading, spacing: stationSpacing) {
                StationRow(row: state.departure, isCancelled: state.isCancelled)
                StationRow(row: state.arrival, isCancelled: state.isCancelled)
            }
            .font(stationFont)
            .padding(.horizontal, textInset)

            // Footer: where next and how long, and which platform.
            HStack(spacing: 4) {
                JourneyChip(
                    background: JourneyPalette.targetBackground,
                    foreground: JourneyPalette.target,
                    font: chipFont,
                    verticalPadding: chipVerticalPadding,
                    horizontalPadding: chipHorizontalPadding,
                    cornerRadius: 100,
                    fillsWidth: true
                ) {
                    TargetLabel(name: drawn.state.targetName, date: drawn.state.targetDate, isStale: drawn.isStale)
                }

                if !Platform.isMissing(drawn.state.platform) {
                    JourneyChip(
                        background: JourneyPalette.platformBackground,
                        font: chipFont,
                        verticalPadding: chipVerticalPadding,
                        horizontalPadding: chipHorizontalPadding,
                        cornerRadius: 100
                    ) {
                        PlatformLabel(
                            platform: Platform.number(drawn.state.platform),
                            isDeparture: drawn.state.isBoardingPlatform,
                            weight: .semibold,
                            scalesToFit: false
                        )
                    }
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
    }
}

// MARK: - Dynamic Island · expanded

/// The island long-pressed open, drawn one region at a time.
///
/// The island is at most 160pt tall and keeps its top row, beside the camera,
/// whether anything is put there or not; the bottom region only starts below it. So
/// the train and the seat go in that top row, and the bottom holds just the two
/// station rows and the chips. With everything in the bottom, the chips were cut off.
struct TrainActivityIslandExpanded: View {
    enum Region { case leading, trailing, bottom }

    let context: TrainActivityContext
    let region: Region

    private let horizontalInset: CGFloat = 4
    /// The top row already clears the camera, so the bottom needs little more.
    private let topInset: CGFloat = 4
    private let bottomInset: CGFloat = 4
    /// Between the station rows and the chips.
    private let footerSpacing: CGFloat = 8

    private let logoHeight: CGFloat = 20
    private let numberFont: Font = .headline
    private let stationFont: Font = .subheadline
    private let chipFont: Font = .subheadline
    /// The platform chip's sides, wider than its top and bottom.
    private let platformHorizontalPadding: CGFloat = 14
    /// The seat chip, sized to stand as tall as the logo and number beside it
    /// (~30pt): the same text as the other chips, with less room around it.
    private let seatFont: Font = .subheadline
    private let seatVerticalPadding: CGFloat = 5
    private let seatHorizontalPadding: CGFloat = 10

    var body: some View {
        switch region {
        case .leading: header
        case .trailing: seat
        case .bottom: journey
        }
    }

    /// Top left: the operator's mark and the train number.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TrainLogo(logo: context.attributes.logo, height: logoHeight)

            Text(context.attributes.number)
                .font(numberFont).fontWeight(.semibold).fontDesign(widgetFontDesign)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.leading, horizontalInset)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Top right: the seat, with a seatbelt rather than a seat, on a darker chip
    /// that holds its own against the island's black.
    @ViewBuilder
    private var seat: some View {
        if let ticket = context.state.ticket, !ticket.label.trimmingCharacters(in: .whitespaces).isEmpty {
            JourneyChip(
                background: JourneyPalette.seatBackground,
                font: seatFont,
                verticalPadding: seatVerticalPadding,
                horizontalPadding: seatHorizontalPadding,
                cornerRadius: 100
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.seated.seatbelt")
                    Text(ticket.label)
                }
            }
            .padding(.trailing, horizontalInset)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    /// Bottom: the two ends of the leg, then where next and which platform.
    private var journey: some View {
        let state = context.state
        let drawn = state.advanced(ifStale: context.isStale)

        return VStack(alignment: .leading, spacing: footerSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                StationRow(row: state.departure, isCancelled: state.isCancelled)
                StationRow(row: state.arrival, isCancelled: state.isCancelled)
            }
            .font(stationFont)

            HStack(spacing: 8) {
                JourneyChip(
                    background: JourneyPalette.targetBackground,
                    foreground: JourneyPalette.target,
                    font: chipFont,
                    fillsWidth: true
                ) {
                    TargetLabel(name: drawn.state.targetName, date: drawn.state.targetDate, isStale: drawn.isStale)
                }

                // Only the number here: "12 Ovest" is too long beside the countdown.
                if !Platform.isMissing(drawn.state.platform) {
                    JourneyChip(
                        background: JourneyPalette.platformBackground,
                        font: chipFont,
                        horizontalPadding: platformHorizontalPadding,
                        cornerRadius: 100
                    ) {
                        PlatformLabel(
                            platform: Platform.number(drawn.state.platform),
                            isDeparture: drawn.state.isBoardingPlatform,
                            weight: .semibold,
                            scalesToFit: false
                        )
                    }
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
    }
}

// MARK: - Dynamic Island · compact

/// The island closed, with the journey on its own: the countdown on the left, the
/// platform on the right — which stop is coming up reads before which side to walk
/// out on.
struct TrainActivityIslandCompact: View {
    enum Side { case leading, trailing }

    let context: TrainActivityContext
    let side: Side

    private let font: Font = .caption
    private let verticalPadding: CGFloat = 4
    private let horizontalPadding: CGFloat = 8

    var body: some View {
        let drawn = context.state.advanced(ifStale: context.isStale)

        switch side {
        case .leading:
            JourneyChip(
                background: JourneyPalette.targetBackground,
                foreground: JourneyPalette.target,
                font: font,
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding
            ) {
                CountdownText(target: drawn.state.targetDate, isStale: drawn.isStale)
            }
        case .trailing:
            // The island keeps this slot either way, so a missing platform holds its
            // place with a dash rather than leaving a hole that reads as a glitch.
            JourneyChip(
                background: JourneyPalette.platformBackground,
                font: font,
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding
            ) {
                PlatformLabel(
                    platform: Platform.isMissing(drawn.state.platform) ? "-" : drawn.state.platform,
                    isDeparture: drawn.state.isBoardingPlatform
                )
            }
        }
    }
}

// MARK: - Dynamic Island · minimal

/// The island shared with another activity: the time left and nothing else, the
/// thing a traveller glances at most.
struct TrainActivityIslandMinimal: View {
    let context: TrainActivityContext

    private let font: Font = .caption2

    var body: some View {
        let drawn = context.state.advanced(ifStale: context.isStale)

        CountdownText(target: drawn.state.targetDate, isStale: drawn.isStale)
            .font(font).fontWeight(.semibold)
            .foregroundStyle(JourneyPalette.target)
    }
}

// MARK: - Shared pieces

/// Every colour the journey views use, named once.
enum JourneyPalette {
    /// The accent: the countdown and nothing else.
    static let target = Color.blue
    static let targetBackground = Color.blue.opacity(0.25)

    /// A time that has slipped, and one that has not.
    static let late = Color.red
    static let onTime = Color.green

    /// Yellow, as the platform has been everywhere in the app.
    static let platformBackground = Color.yellow.opacity(0.5)

    /// A chip that carries no news, like the seat on the Lock Screen.
    static let neutralBackground = Color.gray.opacity(0.3)
    /// The seat in the expanded island, a touch stronger against the island's black.
    static let seatBackground = Color.gray.opacity(0.35)
}

/// Reading the platform the feed sends.
enum Platform {
    /// Not announced yet arrives as "-", "N/A" or nothing at all.
    static func isMissing(_ platform: String) -> Bool {
        let trimmed = platform.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" || trimmed == "N/A"
    }

    /// "12 Ovest" as just "12", for where there is room for the number alone.
    static func number(_ platform: String) -> String {
        let trimmed = platform.trimmingCharacters(in: .whitespaces)
        guard !isMissing(platform) else { return "-" }
        let digits = trimmed.prefix { $0.isNumber }
        return digits.isEmpty ? trimmed : String(digits)
    }
}

/// A rounded chip around a word or two. Every chip here is one of these.
struct JourneyChip<Content: View>: View {
    var background: Color = JourneyPalette.neutralBackground
    var foreground: Color = .primary
    var font: Font = .subheadline
    var verticalPadding: CGFloat = 8
    var horizontalPadding: CGFloat = 12
    var cornerRadius: CGFloat = 16
    var fillsWidth: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(font)
            .fontDesign(widgetFontDesign)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// "Alessandria in 20:27": where the train is heading next, and how long that is.
/// The "in" is what keeps the countdown from reading as a time of day.
struct TargetLabel: View {
    let name: String
    let date: Date
    let isStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            if !name.isEmpty {
                Text(name)
                    .truncationMode(.tail)
                Text("in")
            }
            CountdownText(target: date, isStale: isStale)
        }
    }
}

/// The platform with an arrow up out of a departure platform, or down into an
/// arrival one — the same arrows the details view and the station board use.
struct PlatformLabel: View {
    let platform: String
    let isDeparture: Bool
    var weight: Font.Weight = .medium
    /// Some platforms are written out ("12 Ovest"), so they are made smaller to fit
    /// rather than cut short. Off in the expanded island, which shows the number
    /// alone: there a seat in the top row leaves the bottom a little less height,
    /// and the number shrank for it.
    var scalesToFit: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isDeparture ? "arrow.up.right" : "arrow.down.right")
            Text(verbatim: platform)
                .minimumScaleFactor(scalesToFit ? 0.5 : 1)
        }
        .fontWeight(weight)
        .monospacedDigit()
    }
}

/// One line of a journey: the station on the left, its time on the right.
///
/// The name stays the primary colour; only the time speaks for the delay — red when
/// the train is behind, green when it is not. A cancelled train shows its booked time
/// struck through, in red.
struct StationRow: View {
    let row: TrainActivityAttributes.ContentState.Row
    let isCancelled: Bool

    var body: some View {
        HStack {
            Text(row.name)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(isCancelled ? row.scheduled : row.effective, format: .dateTime.hour().minute())
                .foregroundStyle((isCancelled || row.delay > 0) ? JourneyPalette.late : JourneyPalette.onTime)
                .strikethrough(isCancelled)
                .monospacedDigit()
        }
        .fontDesign(widgetFontDesign)
    }
}

/// The time left to the stop the journey is aimed at.
///
/// It has to keep running with Rail closed, so the system is handed the two dates
/// and counts between them itself. `Text(timerInterval:)` rather than a format style
/// with units, because the units froze: they only moved when the app pushed an
/// update. The cost is "20:27" instead of "20m 27s", which is what `TargetLabel`'s
/// "in" is for. When the target arrives the activity goes stale and this reads "Now".
struct CountdownText: View {
    let target: Date
    let isStale: Bool

    /// Held at least a moment ahead of now: a backwards range traps rather than draws.
    private var interval: ClosedRange<Date> {
        let now = Date()
        return now...max(target, now.addingTimeInterval(1))
    }

    /// The widest the countdown will get, in the same number of digits.
    ///
    /// A timer text takes every point of width it is offered, which pushed the island
    /// wide open, and `fixedSize()` is the one modifier the activity's archive can't
    /// take — the whole chip came back empty. So a hidden text of the same digits
    /// makes the room and the timer is drawn over it. With no hours field ("80:12"),
    /// the width only changes with the digits in the minutes.
    private var widest: String {
        let minutes = target.timeIntervalSinceNow / 60
        if minutes >= 100 { return "000:00" }
        return minutes >= 10 ? "00:00" : "0:00"
    }

    var body: some View {
        Group {
            if isStale {
                Text("Now")
            } else {
                Text(widest)
                    .hidden()
                    .overlay(alignment: .leading) {
                        Text(timerInterval: interval, countsDown: true, showsHours: false)
                            .multilineTextAlignment(.leading)
                    }
            }
        }
        .fontDesign(widgetFontDesign)
        .monospacedDigit()
        // Made smaller when it does not fit, never broken across two lines.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// An operator's mark, sized to sit on a line of text.
///
/// The asset is named by the operator code stored on the train ("FR", "ITALO", …)
/// and lives in the widget extension's catalogue as a vector, declared 50pt tall.
/// Keep new logos at that height: the activity's archive rasterises them at their
/// declared size, and anything over 576 pixels blanks the whole activity.
struct TrainLogo: View {
    let logo: String
    var height: CGFloat = 24

    var body: some View {
        if !logo.isEmpty {
            if UIImage(named: logo) != nil {
                // By name, never `Image(uiImage:)`: that puts the decoded bitmap in
                // the archive, which is enough to stop the activity drawing at all.
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                // A category the app has no badge for falls back to its acronym.
                Text(logo)
                    .font(.caption).fontWeight(.bold)
                    .fontDesign(widgetFontDesign)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Lock Screen", as: .content, using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    // Not departed, with a seat: counting down to boarding.
    TrainActivitySample.state(TrainActivitySample.notDeparted, ticket: TrainActivitySample.ticket)
    // Running, late, and nobody has a seat.
    TrainActivitySample.state(TrainActivitySample.delayed)
    // Past the target: the countdown reads "Now".
    TrainActivitySample.state(TrainActivitySample.arrivingNow, ticket: TrainActivitySample.ticket)
}

#Preview("Island · expanded", as: .dynamicIsland(.expanded), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    TrainActivitySample.state(TrainActivitySample.notDeparted, ticket: TrainActivitySample.ticket)
    TrainActivitySample.state(TrainActivitySample.longNames, ticket: TrainActivitySample.ticket)
}

#Preview("Island · compact", as: .dynamicIsland(.compact), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.noPlatform)
}

#Preview("Island · minimal", as: .dynamicIsland(.minimal), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
}

#endif
