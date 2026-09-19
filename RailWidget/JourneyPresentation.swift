import SwiftUI

/// The pieces a journey is drawn with, in one place so the Live Activity and the
/// widgets cannot drift apart.
///
/// These started out private to the train widget. The Live Activity needs the same
/// station rows, the same yellow platform chip and the same way of saying "this time
/// moved", so they live here now rather than being copied and slowly diverging.

// MARK: - Constants

/// The rounded face the whole app is set in. Declared here rather than borrowed from
/// either target's own constant, because this file is compiled into both and each
/// side spells it differently.
let journeyFontDesign: Font.Design = .rounded

// MARK: - Palette

/// Every colour the journey views use, named once.
///
/// Collected deliberately: tuning the Live Activity means tuning these, not hunting
/// through view bodies for `Color.yellow.opacity(0.5)`.
enum JourneyPalette {
    /// The accent. It marks the stop the countdown is aimed at, and the countdown
    /// itself once it lands.
    static let target = Color.blue

    /// A time that has slipped, and one that has not.
    static let late = Color.red
    static let onTime = Color.green

    /// A time that has not been put to the test yet, so it is merely the timetable.
    static let scheduled = Color.primary

    /// The platform chip, which has been yellow everywhere in the app since long
    /// before there was a Live Activity to put one in.
    static let platformBackground = Color.yellow.opacity(0.5)

    /// The resting background of a capsule that carries no news.
    static let neutralBackground = Color.gray.opacity(0.15)

    /// Backgrounds for a journey that is running late, or cancelled outright.
    static let lateBackground = Color.red.opacity(0.15)
    static let onTimeBackground = Color.green.opacity(0.15)

    /// Every chip in the app is drawn to this radius.
    static let capsuleRadius: CGFloat = 16
}

// MARK: - Logo

/// An operator's mark, sized to sit on a line of text.
///
/// The asset is named by the operator code stored on the train ("FR", "ITALO", …)
/// and lives in the widget extension's own catalogue as a vector, so it costs the
/// Live Activity payload nothing and never outgrows its slot.
struct TrainLogo: View {
    let logo: String
    var height: CGFloat = 24

    var body: some View {
        Image(logo)
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }
}

// MARK: - Times

/// A stop's time, saying by its colour and its value whether the train is keeping to it.
///
/// The rule is the one the train widget has always used. A time is only judged once
/// the train could have been there to keep it: a departure is judged from its own
/// booked time, an arrival from the moment the train was due to pull out of the first
/// stop — before that, a delay reported for a train yet to run is not news.
struct StopTime: View {
    /// The delay-adjusted time.
    let effective: Date
    /// The booked time.
    let scheduled: Date
    let delay: Int
    var isCancelled: Bool = false

    /// An arrival is judged against the start of the journey rather than against
    /// itself, since a train cannot be late for a stop it has not set out towards.
    var isArrival: Bool = false
    var firstDeparture: Date = .distantPast

    /// Passed in so a preview can be staged at a chosen moment.
    var now: Date = Date()

    /// Overrides the colour outright: the stop the countdown is aimed at is blue
    /// whatever its delay is doing.
    var isTarget: Bool = false

    private var reference: Date { isArrival ? firstDeparture : scheduled }
    private var isUnderway: Bool { now >= reference }

    private var color: Color {
        if isTarget { return JourneyPalette.target }
        if isCancelled { return JourneyPalette.late }
        guard isUnderway else { return JourneyPalette.scheduled }
        if delay == 0 { return JourneyPalette.onTime }
        return delay > 0 ? JourneyPalette.late : JourneyPalette.onTime
    }

    /// The booked time stands until the train is actually running against it and
    /// missing it; only then is the moved time the honest one to show.
    private var shown: Date {
        (isCancelled || (isUnderway && delay != 0)) ? effective : scheduled
    }

    var body: some View {
        Text(shown, format: .dateTime.hour().minute())
            .fontDesign(journeyFontDesign)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

// MARK: - Station row

/// One line of a journey: where, on the left, and when, on the right.
struct StationRow: View {
    let name: String
    let time: StopTime

    /// The stop the countdown is aimed at wears the accent on both halves.
    var isTarget: Bool = false

    var body: some View {
        HStack {
            Text(name)
                .fontDesign(journeyFontDesign)
                .foregroundStyle(isTarget ? JourneyPalette.target : Color.primary)
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

    var compact: Bool = false

    /// A platform the feed has not filled in arrives as "-" or as nothing at all.
    static func isMissing(_ platform: String) -> Bool {
        let trimmed = platform.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" || trimmed == "N/A"
    }

    var body: some View {
        if !Self.isMissing(platform) {
            HStack(spacing: 4) {
                Image(systemName: isDeparture ? "arrow.up.right" : "arrow.down.right")
                Text(platform)
            }
            .font(compact ? .caption : .subheadline)
            .fontWeight(.medium)
            .fontDesign(journeyFontDesign)
            .padding(.vertical, compact ? 4 : 8)
            .padding(.horizontal, compact ? 8 : 12)
            .background(JourneyPalette.platformBackground)
            .cornerRadius(JourneyPalette.capsuleRadius)
        }
    }
}

/// A chip carrying a seat, a delay, or whatever else a journey has to say in a word.
struct JourneyCapsule<Content: View>: View {
    var background: Color = JourneyPalette.neutralBackground
    var foreground: Color = .primary
    var fillsWidth: Bool = false
    var compact: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(compact ? .caption : .subheadline)
            .fontDesign(journeyFontDesign)
            .foregroundStyle(foreground)
            .padding(.vertical, compact ? 4 : 8)
            .padding(.horizontal, compact ? 8 : 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(background)
            .cornerRadius(JourneyPalette.capsuleRadius)
    }
}

/// The first passenger's coach and seat, absent when nobody has entered one.
struct SeatCapsule: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        if !label.trimmingCharacters(in: .whitespaces).isEmpty {
            JourneyCapsule(compact: compact) {
                HStack(spacing: 4) {
                    Image(systemName: "carseat.left.fill")
                    Text(label)
                }
            }
        }
    }
}
