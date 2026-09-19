import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Countdown

/// Turns `TimeDataSource.durationOffset(to:)` the right way round.
///
/// That source measures from the target *to now*, so a stop ten minutes off arrives
/// as a duration of -10m and the Lock Screen read "-10m". There is no `from:`
/// counterpart in the framework, so the value is negated on the way through.
///
/// `Text(_:format:)` takes a `DiscreteFormatStyle` rather than any old format style
/// because that is how SwiftUI learns when the text will next change and books a
/// redraw for exactly then — which is what keeps the countdown ticking with the app
/// closed. So those two questions are forwarded as well, with their direction
/// swapped along with the value: as the offset grows, the time remaining shrinks.
/// `input(before:)` and `input(after:)` already have defaults for `Duration`.
struct RemainingTime: DiscreteFormatStyle {
    private let base: Duration.UnitsFormatStyle

    init(_ base: Duration.UnitsFormatStyle) {
        self.base = base
    }

    // `Duration` is only `AdditiveArithmetic`, so there is no unary minus to reach for.
    private func flipped(_ value: Duration) -> Duration { .zero - value }

    func format(_ value: Duration) -> String {
        base.format(flipped(value))
    }

    func discreteInput(before input: Duration) -> Duration? {
        base.discreteInput(after: flipped(input)).map(flipped)
    }

    func discreteInput(after input: Duration) -> Duration? {
        base.discreteInput(before: flipped(input)).map(flipped)
    }

    /// Forwarded rather than left to the protocol's default, which would return the
    /// wrapper untouched and quietly strip the locale off the units underneath.
    func locale(_ locale: Locale) -> RemainingTime {
        RemainingTime(base.locale(locale))
    }
}

/// The time left to the stop the journey is aimed at.
///
/// It has to keep running with Rail closed, so it is never a string this app
/// computes: the system is handed the date and ticks it down itself. When the target
/// arrives the activity goes stale — a flip the system also makes on its own — and
/// the countdown becomes "Now".
struct CountdownText: View {

    /// How much of the remaining time is spelled out.
    enum Detail {
        /// Two units: "1h 25m" over an hour, "10m 50s" under it. Allowing seconds is
        /// what makes the two-unit rule fall out on its own — the largest two units
        /// that are not zero are exactly the pair we want at either range.
        case full
        /// One unit: "1h", "50m". For the island, where there is room for a glance
        /// and nothing more.
        case single
    }

    let target: Date
    let isStale: Bool
    var detail: Detail = .full

    var body: some View {
        Group {
            if isStale {
                Text("Now")
            } else {
                switch detail {
                case .full:
                    Text(
                        TimeDataSource<Duration>.durationOffset(to: target),
                        format: RemainingTime(
                            .units(
                                allowed: [.hours, .minutes, .seconds],
                                width: .narrow,
                                maximumUnitCount: 2,
                                fractionalPart: .hide(rounded: .down)
                            )
                        )
                    )
                case .single:
                    Text(
                        TimeDataSource<Duration>.durationOffset(to: target),
                        format: RemainingTime(
                            .units(
                                allowed: [.hours, .minutes],
                                width: .narrow,
                                maximumUnitCount: 1,
                                fractionalPart: .hide(rounded: .down)
                            )
                        )
                    )
                }
            }
        }
        .fontDesign(journeyFontDesign)
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: true))
    }
}

/// The blue chip: where the train is heading next, and how long that is.
///
/// This is where a stop between the two ends of the journey gets its name said —
/// "Alessandria · 10m 50s" — rather than taking a row of its own.
struct TargetCapsule: View {
    let name: String
    let target: Date
    let isStale: Bool

    /// Dropped in the island, where only the time fits.
    var showsName: Bool = true
    var detail: CountdownText.Detail = .full
    var compact: Bool = false

    var body: some View {
        JourneyCapsule(
            background: JourneyPalette.targetBackground,
            foreground: JourneyPalette.target,
            fillsWidth: showsName,
            compact: compact
        ) {
            HStack(spacing: 6) {
                if showsName, !name.isEmpty {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                CountdownText(target: target, isStale: isStale, detail: detail)
            }
        }
    }
}

// MARK: - Lock Screen

/// The journey in three bands: which train and which seat, the two ends of the leg,
/// and what is left to wait.
struct TrainActivityView: View {
    let context: ActivityViewContext<TrainActivityAttributes>

    private var state: TrainActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(spacing: 10) {
            header
            stations
            footer
        }
        .padding(.horizontal, JourneyMetrics.lockScreenHorizontal)
        .padding(.vertical, JourneyMetrics.lockScreenVertical)
        // Low enough to keep the wallpaper showing through, which is what makes the
        // whole thing read as glass rather than as a card.
        .activityBackgroundTint(Color.black.opacity(0.12))
        .activitySystemActionForegroundColor(JourneyPalette.target)
        .widgetURL(TrainActivityLinks.journey(context.attributes))
    }

    // MARK: Bands

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TrainLogo(logo: context.attributes.logo, height: 22)

            Text(context.attributes.number)
                .font(.title3).fontWeight(.semibold).fontDesign(journeyFontDesign)
                .foregroundStyle(Color.primary)

            Spacer()

            // A tap here goes straight to the QR code rather than to the journey.
            if let seat = TrainActivityLinks.seat(context.attributes) {
                Link(destination: seat) {
                    SeatCapsule(label: context.attributes.seatLabel)
                }
            } else {
                SeatCapsule(label: context.attributes.seatLabel)
            }
        }
    }

    private var stations: some View {
        VStack(alignment: .leading, spacing: 4) {
            stationRow(state.departure, role: .departure, isDepartureSide: true)
            stationRow(state.arrival, role: .arrival, isDepartureSide: false)
        }
        .font(.subheadline)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TargetCapsule(
                name: state.targetName,
                target: state.targetDate,
                isStale: context.isStale
            )

            PlatformCapsule(
                platform: state.platform,
                isDeparture: state.isBoardingPlatform
            )
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func stationRow(
        _ row: TrainActivityAttributes.ContentState.Row,
        role: TrainActivityAttributes.ContentState.TargetRole,
        isDepartureSide: Bool
    ) -> some View {
        // Blue only when the countdown is aimed at this very row. While the train is
        // heading for a stop in between, neither row is the target and the blue is
        // carried by the chip below.
        let isTarget = state.targetRole == role

        StationRow(
            name: row.name,
            time: StopTime(
                effective: row.effective,
                scheduled: row.scheduled,
                delay: row.delay,
                isCancelled: state.isCancelled,
                isArrival: !isDepartureSide,
                firstDeparture: state.departure.effective,
                isTarget: isTarget
            ),
            isTarget: isTarget
        )
    }
}

// MARK: - Deep links

/// Where a tap goes. Both forms are ones the app already answers.
enum TrainActivityLinks {
    static func journey(_ attributes: TrainActivityAttributes) -> URL? {
        URL(string: "railapp://view-train?trainID=\(attributes.trainID.uuidString)")
    }

    /// The journey *and* the seat's QR code, which is what the ticket widget's tap
    /// has always opened.
    static func seat(_ attributes: TrainActivityAttributes) -> URL? {
        guard let seatID = attributes.seatID, !attributes.seatLabel.isEmpty else { return nil }
        return URL(
            string: "railapp://view-ticket?trainID=\(attributes.trainID.uuidString)&seatID=\(seatID.uuidString)"
        )
    }
}

// MARK: - Configuration

struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            TrainActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Leading and trailing share the top line, and the centre region
                // competes with them for it — filling the centre pushed the logo and
                // the seat out of the island entirely. Everything below the top line
                // goes in the bottom region instead, which has the width to itself.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        TrainLogo(logo: context.attributes.logo, height: 18)
                        Text(context.attributes.number)
                            .font(.subheadline).fontWeight(.semibold)
                            .fontDesign(journeyFontDesign)
                    }
                    .padding(.leading, JourneyMetrics.islandHorizontal)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let seat = TrainActivityLinks.seat(context.attributes) {
                        Link(destination: seat) {
                            SeatCapsule(label: context.attributes.seatLabel, compact: true)
                        }
                        .padding(.trailing, JourneyMetrics.islandHorizontal)
                    } else {
                        SeatCapsule(label: context.attributes.seatLabel, compact: true)
                            .padding(.trailing, JourneyMetrics.islandHorizontal)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            islandRow(context, context.state.departure, role: .departure, isDepartureSide: true)
                            islandRow(context, context.state.arrival, role: .arrival, isDepartureSide: false)
                        }
                        .font(.footnote)

                        HStack(spacing: 8) {
                            TargetCapsule(
                                name: context.state.targetName,
                                target: context.state.targetDate,
                                isStale: context.isStale,
                                compact: true
                            )

                            PlatformCapsule(
                                platform: context.state.platform,
                                isDeparture: context.state.isBoardingPlatform,
                                compact: true
                            )
                        }
                    }
                    // The island clips its regions at the edge, which was trimming
                    // both chips; this keeps them whole.
                    .padding(.horizontal, JourneyMetrics.islandHorizontal)
                }
            } compactLeading: {
                PlatformCapsule(
                    platform: context.state.platform,
                    isDeparture: context.state.isBoardingPlatform,
                    compact: true
                )
            } compactTrailing: {
                TargetCapsule(
                    name: "",
                    target: context.state.targetDate,
                    isStale: context.isStale,
                    showsName: false,
                    detail: .single,
                    compact: true
                )
                .font(.caption)
            } minimal: {
                // Shown when the island is shared with another activity. The platform
                // is dropped here: the one thing worth the space is how long is left.
                TargetCapsule(
                    name: "",
                    target: context.state.targetDate,
                    isStale: context.isStale,
                    showsName: false,
                    detail: .single,
                    compact: true
                )
                .font(.caption2)
            }
            .widgetURL(TrainActivityLinks.journey(context.attributes))
            .keylineTint(JourneyPalette.target)
        }
    }

    /// The same row the Lock Screen draws, so a delay is coloured identically in
    /// both places.
    private func islandRow(
        _ context: ActivityViewContext<TrainActivityAttributes>,
        _ row: TrainActivityAttributes.ContentState.Row,
        role: TrainActivityAttributes.ContentState.TargetRole,
        isDepartureSide: Bool
    ) -> some View {
        let isTarget = context.state.targetRole == role

        return StationRow(
            name: row.name,
            time: StopTime(
                effective: row.effective,
                scheduled: row.scheduled,
                delay: row.delay,
                isCancelled: context.state.isCancelled,
                isArrival: !isDepartureSide,
                firstDeparture: context.state.departure.effective,
                isTarget: isTarget
            ),
            isTarget: isTarget
        )
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Lock Screen", as: .content, using: TrainActivitySample.withSeat) {
    TrainLiveActivity()
} contentStates: {
    // Not departed: the boarding row is blue, and the chip names it too.
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    // Running towards a stop in between: neither row is blue, the chip carries it.
    TrainActivitySample.state(TrainActivitySample.enRoute)
    // A leg inside a longer service, boarding and alighting mid-route.
    TrainActivitySample.state(TrainActivitySample.midRoute)
    // Nothing left before the end: the arrival row goes blue.
    TrainActivitySample.state(TrainActivitySample.nextIsArrival)
    // The target is behind us, so the activity is stale and reads "Now".
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
    // Twelve down, which is where the shown times stop being the timetable's.
    TrainActivitySample.state(TrainActivitySample.delayed)
    // No platform announced: no yellow chip.
    TrainActivitySample.state(TrainActivitySample.noPlatform)
}

#Preview("Lock Screen · no seat", as: .content, using: TrainActivitySample.withoutSeat) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.longNames)
}

#Preview("Lock Screen · several passengers", as: .content, using: TrainActivitySample.manyPassengers) {
    TrainLiveActivity()
} contentStates: {
    // Several are travelling; only the first one's seat is shown.
    TrainActivitySample.state(TrainActivitySample.enRoute)
}

#Preview("Island · expanded", as: .dynamicIsland(.expanded), using: TrainActivitySample.withSeat) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
    TrainActivitySample.state(TrainActivitySample.noPlatform)
    TrainActivitySample.state(TrainActivitySample.longNames)
}

#Preview("Island · compact", as: .dynamicIsland(.compact), using: TrainActivitySample.withSeat) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
    TrainActivitySample.state(TrainActivitySample.noPlatform)
}

#Preview("Island · minimal", as: .dynamicIsland(.minimal), using: TrainActivitySample.withSeat) {
    TrainLiveActivity()
} contentStates: {
    TrainActivitySample.state(TrainActivitySample.enRoute)
    TrainActivitySample.state(TrainActivitySample.arrivingNow)
}

#endif
