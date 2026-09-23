import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

// A journey on the Lock Screen, in the Dynamic Island and on the Apple Watch's Smart
// Stack: the configuration, every view it draws, and its previews at the bottom.
//
// What the activity carries, and the rules that decide it, are in `TrainActivity.swift`.

// MARK: - Configuration

struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            TrainActivityView(context: context)
        } dynamicIsland: { context in
            // Every presentation draws the same target: once the activity has gone stale
            // that is the stop after the one it was counting to, if the app knew it.
            let drawn = context.state.advanced(ifStale: context.isStale)

            return DynamicIsland {
                // The island is a glance, not a screen. Repeating the two ends of the
                // leg and the train number here only made it cramped, so it keeps the
                // two things worth looking up for — how long, and which platform —
                // and draws them large.
                // In the bottom region rather than the centre: this is the one
                // that has drawn reliably here, and the centre competes with the
                // leading and trailing slots even when they are empty.
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        TargetCapsule(
                            name: drawn.state.targetName,
                            target: drawn.state.targetDate,
                            isStale: drawn.isStale,
                            size: .prominent
                        )

                        PlatformCapsule(
                            platform: drawn.state.platform,
                            isDeparture: drawn.state.isBoardingPlatform,
                            size: .prominent,
                            showsPlaceholder: true
                        )
                    }
                    .padding(.horizontal, JourneyMetrics.islandHorizontal)
                    .padding(.vertical, 4)
                }
            } compactLeading: {
                PlatformCapsule(
                    platform: drawn.state.platform,
                    isDeparture: drawn.state.isBoardingPlatform,
                    size: .compact,
                    showsPlaceholder: true
                )
            } compactTrailing: {
                TargetCapsule(
                    name: "",
                    target: drawn.state.targetDate,
                    isStale: drawn.isStale,
                    showsName: false,
                    size: .compact
                )
            } minimal: {
                // Shown when the island is shared with another activity. Just the
                // platform, in its yellow circle: two digits are all that reads there.
                PlatformBadge(platform: drawn.state.platform)
            }
            .widgetURL(TrainActivityLinks.journey(context.attributes))
            .keylineTint(JourneyPalette.target)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Activity view

/// What the system actually asks for. It asks twice over: for the Lock Screen, which
/// is the medium family, and for the Apple Watch's Smart Stack, which is the small one.
struct TrainActivityView: View {
    let context: ActivityViewContext<TrainActivityAttributes>

    @Environment(\.activityFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .small:
                TrainActivityWatch(
                    attributes: context.attributes,
                    state: context.state,
                    isStale: context.isStale
                )
            default:
                TrainActivityLockScreen(
                    attributes: context.attributes,
                    state: context.state,
                    isStale: context.isStale
                )
                // Low enough to keep the wallpaper showing through, which is what makes
                // the whole thing read as glass rather than as a card.
                .activityBackgroundTint(Color.black.opacity(0.12))
                .activitySystemActionForegroundColor(JourneyPalette.target)
            }
        }
        .widgetURL(TrainActivityLinks.journey(context.attributes))
    }
}

// MARK: - Lock Screen

/// The journey in three bands: which train and which seat, the two ends of the leg,
/// and what is left to wait.
///
/// Takes plain values rather than an `ActivityViewContext`, which cannot be built by
/// hand, so the Lock Screen and the Watch card can share the same inputs.
struct TrainActivityLockScreen: View {
    let attributes: TrainActivityAttributes
    let state: TrainActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 10) {
            header
            stations
            footer
        }
        .padding(.horizontal, JourneyMetrics.lockScreenHorizontal)
        .padding(.vertical, JourneyMetrics.lockScreenVertical)
        .padding(.bottom, -4)
    }

    // MARK: Bands

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TrainLogo(logo: attributes.logo, height: 22)
                .padding(.leading, JourneyMetrics.lockScreenTextInset)

            Text(attributes.number)
                .font(.title3).fontWeight(.semibold).fontDesign(widgetFontDesign)
                .foregroundStyle(Color.primary)

            Spacer()

            // Only a passenger with a coach or a seat is shown, and only here: the
            // island has no room for it. A tap goes straight to their ticket rather
            // than to the journey.
            if let ticket = state.ticket, let link = TrainActivityLinks.seat(attributes, ticket) {
                Link(destination: link) {
                    SeatCapsule(label: ticket.label)
                }
            }
        }
        .padding(.top, -4)
    }

    private var stations: some View {
        VStack(alignment: .leading, spacing: 4) {
            stationRow(state.departure)
            stationRow(state.arrival)
        }
        .font(.subheadline)
        .padding(.horizontal, JourneyMetrics.lockScreenTextInset)
    }

    private var footer: some View {
        // Passing the stop it was counting to moves the chips on to the next one, with
        // no update from the app; see `ContentState.advanced(ifStale:)`.
        let drawn = state.advanced(ifStale: isStale)

        return HStack(spacing: 8) {
            TargetCapsule(
                name: drawn.state.targetName,
                target: drawn.state.targetDate,
                isStale: drawn.isStale
            )

            PlatformCapsule(
                platform: drawn.state.platform,
                isDeparture: drawn.state.isBoardingPlatform
            )
        }
    }

    // MARK: Rows

    private func stationRow(_ row: TrainActivityAttributes.ContentState.Row) -> some View {
        StationRow(
            name: row.name,
            time: StopTime(
                effective: row.effective,
                scheduled: row.scheduled,
                delay: row.delay,
                isCancelled: state.isCancelled
            )
        )
    }
}

// MARK: - Apple Watch

/// The journey on the Smart Stack: three rows, all set flush against the card's
/// leading edge.
///
/// A small header names the train; the next station's name gets a full-width row of
/// its own beneath it, since that is the one piece of text here worth room to breathe;
/// and the countdown to it shares its row with the platform, the two things read
/// together at a glance. The delays, the seat and the rest of the stops are left to
/// the phone.
struct TrainActivityWatch: View {
    let attributes: TrainActivityAttributes
    let state: TrainActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let drawn = state.advanced(ifStale: isStale)

        return VStack(alignment: .leading, spacing: WatchMetrics.rowSpacing) {
            HStack(spacing: WatchMetrics.logoSpacing) {
                TrainLogo(logo: attributes.logo, height: WatchMetrics.logoHeight)

                Text(attributes.number)
                    .font(WatchMetrics.numberFont).fontWeight(.semibold).fontDesign(widgetFontDesign)
                    .foregroundStyle(Color.primary)
            }

            VStack(alignment: .leading, spacing: WatchMetrics.stationSpacing) {
                Text(drawn.state.targetName)
                    .font(WatchMetrics.stationFont)
                    .fontDesign(widgetFontDesign)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: WatchMetrics.chipSpacing) {
                    CountdownText(target: drawn.state.targetDate, isStale: drawn.isStale)
                        .font(WatchMetrics.countdownFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)

                    Spacer(minLength: 4)

                    PlatformCapsule(
                        platform: drawn.state.platform,
                        isDeparture: drawn.state.isBoardingPlatform,
                        size: .watch
                    )
                }
                // Without this the row only ever hugs the countdown and the
                // platform is left wherever their 4pt gap happens to land it. The
                // full width is what gives the spacer between them something to
                // expand into, so the badge lands flush against the trailing edge —
                // concentric with the card's own corner, the way `chipCornerRadius`
                // already assumes it will be.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, WatchMetrics.contentInset)
        .padding(.vertical, WatchMetrics.contentVerticalInset)
    }
}

// MARK: - Countdown

/// The time left to the stop the journey is aimed at.
///
/// It has to keep running with Rail closed, so it is never a string this app
/// computes: the system is handed the two dates and counts between them itself.
/// When the target arrives the activity goes stale — a flip the system also makes on
/// its own — and the countdown becomes "Now".
///
/// This is `Text(timerInterval:)` rather than a format style with units, and the
/// reason is that the units froze. `Text(_:format:)` over a `TimeDataSource` stopped
/// at whatever value it was first given and only moved when the app itself pushed an
/// update, which defeats the entire point. `timerInterval` is the older, plainer
/// thing and it does tick on its own.
///
/// The cost is the wording: "20:27" instead of "20m 27s", which on a screen full of
/// station times could be mistaken for a clock. That is what the "in" in front of it
/// is for — "Alessandria in 20:27" can only be read as a wait.
struct CountdownText: View {

    let target: Date
    let isStale: Bool

    /// The range has to run forwards, so the target is held at least a moment ahead
    /// of now. In practice the stale date takes over at exactly that point and this
    /// never shows, but a backwards range would trap rather than draw.
    private var interval: ClosedRange<Date> {
        let now = Date()
        return now...max(target, now.addingTimeInterval(1))
    }

    /// The widest the countdown will get, spelled with the same number of digits.
    ///
    /// A timer text takes every point of width it is offered, which is what pushed the
    /// Dynamic Island wide open. It cannot be told its own size with `fixedSize()`:
    /// that is the one modifier here the Live Activity's archive cannot take, and the
    /// whole chip comes back empty. So the room is made by a plain text of the same
    /// digits, and the timer is drawn over it, which offers it exactly that width.
    ///
    /// The timer has no hours field, so it reads "80:12" for an hour and twenty rather
    /// than "1:20:12". That matters for the width: an activity starts an hour before
    /// boarding, right on the line where the hours form gives way to the minutes one,
    /// and a slot sized for the wrong side of it was left with blank space beside the
    /// time. Without hours the width only changes with the digits in the minutes.
    ///
    /// Digits are monospaced, so the placeholder is as wide as the real thing at every
    /// tick. It is picked from how far off the target is when the content changes; a
    /// countdown only ever gets shorter, so the slot is only ever a digit too roomy.
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
        // A countdown that does not fit is made smaller, never broken across two lines.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The blue chip: where the train is heading next, and how long that is.
///
/// This is where a stop between the two ends of the journey gets its name said —
/// "Alessandria in 20:27" — rather than taking a row of its own.
struct TargetCapsule: View {
    let name: String
    let target: Date
    let isStale: Bool

    /// Dropped in the island, where only the time fits.
    var showsName: Bool = true
    var size: JourneyChipSize = .regular

    var body: some View {
        JourneyCapsule(
            background: JourneyPalette.targetBackground,
            foreground: JourneyPalette.target,
            fillsWidth: showsName,
            size: size
        ) {
            HStack(spacing: 4) {
                if showsName, !name.isEmpty {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Without this the countdown reads as a time of day.
                    Text("in")
                }

                CountdownText(target: target, isStale: isStale)
            }
        }
    }
}

// MARK: - Logo

/// An operator's mark, sized to sit on a line of text.
///
/// The asset is named by the operator code stored on the train ("FR", "ITALO", …)
/// and lives in the widget extension's own catalogue as a vector.
///
/// The declared size of each SVG matters more than it looks. A Live Activity's view
/// is archived with the image rasterised at that size, and the system swaps any image
/// taller than 576 pixels for a placeholder and then fails to load the whole archive —
/// the activity stays blank. At the 200pt the logos were exported at, that is 600
/// pixels on a 3x screen. They are declared at 50pt tall now, which is still more than
/// twice what the largest place they are drawn (22pt) needs, and is quicker to archive.
/// Keep any new logo at that height.
struct TrainLogo: View {
    let logo: String
    var height: CGFloat = 24

    var body: some View {
        if !logo.isEmpty {
            if UIImage(named: logo) != nil {
                // Referenced by name, never as an image. A Live Activity's view is
                // archived to be redrawn elsewhere, and `Image(uiImage:)` puts the
                // decoded bitmap in that archive rather than a name to look up —
                // enough to stop the whole activity drawing at all.
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                // Trenitalia prints categories the app has no badge for. The station
                // board has always fallen back to the acronym itself; so does this.
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

// MARK: - Times

/// A stop's time, coloured the way the train details view colours it.
///
/// The moved time is the one shown, red when the train is behind and green when it is
/// not — on time or early. A cancelled train shows its booked time, struck through, in
/// red. There is no in-between colour: a Live Activity only exists for a journey that
/// is about to run or running, which is exactly when the details view colours it too.
struct StopTime: View {
    /// The delay-adjusted time.
    let effective: Date
    /// The booked time.
    let scheduled: Date
    let delay: Int
    var isCancelled: Bool = false

    private var color: Color {
        (isCancelled || delay > 0) ? JourneyPalette.late : JourneyPalette.onTime
    }

    private var shown: Date {
        isCancelled ? scheduled : effective
    }

    var body: some View {
        Text(shown, format: .dateTime.hour().minute())
            .fontDesign(widgetFontDesign)
            .foregroundStyle(color)
            .strikethrough(isCancelled)
            .monospacedDigit()
    }
}

// MARK: - Station row

/// One line of a journey: where, on the left, and when, on the right.
///
/// The name is always the primary colour. Only the time speaks for the delay.
struct StationRow: View {
    let name: String
    let time: StopTime

    var body: some View {
        HStack {
            Text(name)
                .fontDesign(widgetFontDesign)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            time
        }
    }
}

// MARK: - Capsules

/// The yellow platform chip, and its long-standing habit of simply not being there
/// when the operator has not said which platform yet.
struct PlatformCapsule: View {
    let platform: String

    /// Points up out of a departure platform, down into an arrival one — the same
    /// pair of arrows the details view and the station board use.
    var isDeparture: Bool = true

    var size: JourneyChipSize = .regular

    /// The Dynamic Island reserves a slot for this chip; leaving it out entirely when
    /// the platform is missing reads as a layout glitch rather than "not announced
    /// yet". There it holds its place with the arrow and a dash rather than vanishing.
    /// Elsewhere — the Lock Screen, the Watch card — there is no fixed slot to leave a
    /// hole in, so the chip keeps disappearing there instead.
    var showsPlaceholder: Bool = false

    /// A platform the feed has not filled in arrives as "-" or as nothing at all.
    static func isMissing(_ platform: String) -> Bool {
        let trimmed = platform.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" || trimmed == "N/A"
    }

    var body: some View {
        let isMissing = Self.isMissing(platform)

        if !isMissing || showsPlaceholder {
            HStack(spacing: 4) {
                Image(systemName: isDeparture ? "arrow.up.right" : "arrow.down.right")
                    // Its own font, apart from the text: on the Watch the number
                    // is the thing that carries the size, and a full-sized arrow
                    // beside it only crowded the number rather than reading with it.
                    .font(size.iconFont)

                Text(isMissing ? "-" : platform)
                    .font(size.font)
                    // A platform is usually a number, but some are written out
                    // ("12 Ovest"). Made smaller to fit, not cut short.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .fontWeight(.medium)
            .fontDesign(widgetFontDesign)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .background(JourneyPalette.platformBackground)
            .cornerRadius(size.cornerRadius)
        }
    }
}

/// How large a chip is drawn.
enum JourneyChipSize {
    /// The Dynamic Island's compact slots, where a glance is all there is room for.
    case compact
    /// The Lock Screen.
    case regular
    /// The expanded island, which has the room to make the two things that matter big.
    case prominent
    /// The Apple Watch: two chips and nothing else on the card, so as large as they fit.
    case watch

    var font: Font {
        switch self {
        case .compact: .caption
        case .regular: .subheadline
        case .prominent: .title3
        case .watch: WatchMetrics.chipFont
        }
    }

    /// The arrow's own font. The same as the platform number everywhere but the
    /// Watch, where the number was made bigger on its own and the arrow staying
    /// behind is what keeps it from crowding the number out.
    var iconFont: Font {
        switch self {
        case .watch: WatchMetrics.chipIconFont
        default: font
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 4
        case .regular: 8
        case .prominent: 10
        case .watch: WatchMetrics.chipVerticalPadding
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 12
        case .prominent: 16
        case .watch: WatchMetrics.chipHorizontalPadding
        }
    }

    /// Larger than half the chip's height on the prominent size, which the shape
    /// clamps to a full pill: the big chips in the expanded island look squarish
    /// at the radius the small ones are drawn to.
    var cornerRadius: CGFloat {
        switch self {
        case .compact, .regular: JourneyPalette.capsuleRadius
        case .prominent: 32
        case .watch: WatchMetrics.chipCornerRadius
        }
    }
}

/// The yellow circle the island shows when it is shared with another activity: the
/// platform, and nothing else.
///
/// No arrow and no time. Just the number — a dash when it has not been announced.
struct PlatformBadge: View {
    let platform: String

    /// Equal on every side, not a fixed diameter: this slot is what is left of the
    /// island once another activity has taken the rest of it, and that is not
    /// reliably a perfect circle to size a fixed frame against.
    private let padding: CGFloat = 6

    /// A platform like "1 Tronco" or "12 Ovest" carries its track's own name after the
    /// number; here there is room for the number alone, so only that is kept. Not
    /// announced yet reads the same dash the rest of the app uses for it.
    private var number: String {
        let trimmed = platform.trimmingCharacters(in: .whitespaces)
        guard !PlatformCapsule.isMissing(platform) else { return "-" }
        let digits = trimmed.prefix { $0.isNumber }
        return digits.isEmpty ? trimmed : String(digits)
    }

    var body: some View {
        Text(verbatim: number)
            .font(.footnote).fontWeight(.semibold)
            .fontDesign(widgetFontDesign)
            .monospacedDigit()
            .padding(padding)
            .background(JourneyPalette.platformBackground, in: Circle())
    }
}

/// A chip carrying a seat, a countdown, or whatever else a journey has to say in a word.
struct JourneyCapsule<Content: View>: View {
    var background: Color = JourneyPalette.neutralBackground
    var foreground: Color = .primary
    var fillsWidth: Bool = false
    var size: JourneyChipSize = .regular
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(size.font)
            .fontDesign(widgetFontDesign)
            .foregroundStyle(foreground)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(background)
            .cornerRadius(size.cornerRadius)
    }
}

/// The first passenger's coach and seat, absent when nobody has entered one.
struct SeatCapsule: View {
    let label: String
    var size: JourneyChipSize = .regular

    var body: some View {
        if !label.trimmingCharacters(in: .whitespaces).isEmpty {
            JourneyCapsule(size: size) {
                HStack(spacing: 4) {
                    Image(systemName: "carseat.left.fill")
                    Text(label)
                }
            }
        }
    }
}

// MARK: - Palette

/// Every colour the journey views use, named once.
///
/// Collected deliberately: tuning the Live Activity means tuning these, not hunting
/// through view bodies for `Color.yellow.opacity(0.5)`.
enum JourneyPalette {
    /// The accent. It belongs to the countdown chip and nothing else: the station
    /// rows stay in the primary colour and let their times carry the delay.
    static let target = Color.blue

    /// A time that has slipped, and one that has not.
    static let late = Color.red
    static let onTime = Color.green

    /// A time that has not been put to the test yet, so it is merely the timetable.
    static let scheduled = Color.primary

    /// The platform chip, which has been yellow everywhere in the app since long
    /// before there was a Live Activity to put one in.
    static let platformBackground = Color.yellow.opacity(0.5)

    /// The countdown's chip. Blue is the accent, so the one thing the journey is
    /// counting towards wears it wherever it appears.
    static let targetBackground = Color.blue.opacity(0.25)

    /// The resting background of a capsule that carries no news.
    static let neutralBackground = Color.gray.opacity(0.15)

    /// Backgrounds for a journey that is running late, or cancelled outright.
    static let lateBackground = Color.red.opacity(0.15)
    static let onTimeBackground = Color.green.opacity(0.15)

    /// Every chip in the app is drawn to this radius.
    static let capsuleRadius: CGFloat = 16
}

// MARK: - Metrics

/// The insets, gathered so the Live Activity's chips can be lined up with the
/// container's own rounded edge without hunting through view bodies.
enum JourneyMetrics {
    /// The Lock Screen's own corner is rounded a good deal more than a chip is, so
    /// the chips sit close to the edge: the gap between the two radii is all the
    /// inset a concentric look wants.
    static let lockScreenHorizontal: CGFloat = 8
    static let lockScreenVertical: CGFloat = 12

    /// How far the Lock Screen's text is set in from the chips' edge: the station rows,
    /// and the logo at the head of the card, so they start on the same line.
    static let lockScreenTextInset: CGFloat = 4

    /// The island clips its regions hard at the edges, so its content is pulled in
    /// rather than pushed out.
    static let islandHorizontal: CGFloat = 6
}

// MARK: - Apple Watch

/// Everything to change to tune the Smart Stack card, in one place.
///
/// The card is drawn by `TrainActivityWatch`.
enum WatchMetrics {
    /// The gap between the header row and the station name below it.
    static let rowSpacing: CGFloat = 12
    /// The gap between the station name and the countdown/platform row right under
    /// it — the two are read as one thought, so they sit closer together than the
    /// header does to either.
    static let stationSpacing: CGFloat = 2
    static let chipSpacing: CGFloat = 6

    /// How far the content is set in from the card's edge, left and right. Kept apart
    /// from `contentVerticalInset` because the two edges are not the same: the system
    /// already leaves the sides some room, but nothing above the header or below the
    /// platform row, which otherwise sat flush against the card's own top and bottom.
    static let contentInset: CGFloat = 8
    static let contentVerticalInset: CGFloat = 14

    /// The header row: the operator's mark and the train number. Kept small and out of
    /// the way — this card's job is to say what is next and where from, not to repeat
    /// the number the passenger already knows they boarded.
    static let logoHeight: CGFloat = 12
    static let logoSpacing: CGFloat = 4
    static let numberFont: Font = .caption2

    /// The next station's name, above its countdown.
    static let stationFont: Font = .subheadline

    /// The countdown and the platform badge, read together at a glance — set to the
    /// same size so neither reads as the lesser of the two.
    static let countdownFont: Font = .title3

    /// The platform badge. Matches `countdownFont`: on the Lock Screen it stays
    /// secondary to the time, but here the two share a row and neither should look
    /// like an afterthought next to the other.
    static let chipFont: Font = .title3
    static let chipVerticalPadding: CGFloat = 4
    static let chipHorizontalPadding: CGFloat = 8

    /// The arrow beside the platform number, held below `chipFont` on its own — see
    /// `JourneyChipSize.iconFont`.
    static let chipIconFont: Font = .caption2

    /// Set well past half the badge's own height, so the corner radius clamps to a
    /// full capsule rather than a rounded rectangle whatever size the badge ends up.
    static let chipCornerRadius: CGFloat = 24
}

// MARK: - Previews

#if DEBUG

#Preview("Lock Screen", as: .content, using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    // Not departed: the chip counts down to boarding.
    TrainActivitySample.state(TrainActivitySample.notDeparted, ticket: TrainActivitySample.ticket)
    // Running towards a stop in between: only the chip names it.
    TrainActivitySample.state(TrainActivitySample.enRoute, ticket: TrainActivitySample.ticket)
    // A leg inside a longer service, boarding and alighting mid-route.
    TrainActivitySample.state(TrainActivitySample.midRoute, ticket: TrainActivitySample.ticket)
    // Nothing left before the end: the chip counts down to arrival.
    TrainActivitySample.state(TrainActivitySample.nextIsArrival, ticket: TrainActivitySample.ticket)
    // The target is behind us, so the activity is stale and reads "Now".
    TrainActivitySample.state(TrainActivitySample.arrivingNow, ticket: TrainActivitySample.ticket)
    // Twelve down, which is where the shown times stop being the timetable's.
    TrainActivitySample.state(TrainActivitySample.delayed, ticket: TrainActivitySample.ticket)
    // No platform announced: no yellow chip.
    TrainActivitySample.state(TrainActivitySample.noPlatform, ticket: TrainActivitySample.ticket)
}

#Preview("Lock Screen · no ticket", as: .content, using: TrainActivitySample.italo) {
    TrainLiveActivity()
} contentStates: {
    // Nobody has a seat, so the top-right corner is empty.
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.longNames)
}

// The Apple Watch card has no preview. Xcode has no canvas for the `.small` family,
// and a hand-sized stand-in never matched the real card, so it is checked on a watch.

#Preview("Island · expanded", as: .dynamicIsland(.expanded), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
    TrainActivitySample.state(TrainActivitySample.noPlatform)
    TrainActivitySample.state(TrainActivitySample.longNames)
}

#Preview("Island · compact", as: .dynamicIsland(.compact), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
    TrainActivitySample.state(TrainActivitySample.noPlatform)
}

#Preview("Island · minimal", as: .dynamicIsland(.minimal), using: TrainActivitySample.attributes) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
}

#endif
