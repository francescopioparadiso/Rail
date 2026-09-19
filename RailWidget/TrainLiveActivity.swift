import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

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

    var body: some View {
        Group {
            if isStale {
                Text("Now")
            } else {
                Text(timerInterval: interval, countsDown: true)
                    // Left to itself it takes all the width it is offered, which is
                    // what pushed the Dynamic Island wide open.
                    .fixedSize()
            }
        }
        .fontDesign(journeyFontDesign)
        .monospacedDigit()
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
                // The island is a glance, not a screen. Repeating the two ends of the
                // leg and the train number here only made it cramped, so it keeps the
                // two things worth looking up for — how long, and which platform —
                // and draws them large.
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 10) {
                        TargetCapsule(
                            name: context.state.targetName,
                            target: context.state.targetDate,
                            isStale: context.isStale,
                            size: .prominent
                        )

                        PlatformCapsule(
                            platform: context.state.platform,
                            isDeparture: context.state.isBoardingPlatform,
                            size: .prominent
                        )
                    }
                    .padding(.horizontal, JourneyMetrics.islandHorizontal)
                    .padding(.top, 4)
                }
            } compactLeading: {
                PlatformCapsule(
                    platform: context.state.platform,
                    isDeparture: context.state.isBoardingPlatform,
                    size: .compact
                )
            } compactTrailing: {
                TargetCapsule(
                    name: "",
                    target: context.state.targetDate,
                    isStale: context.isStale,
                    showsName: false,
                    size: .compact
                )
            } minimal: {
                // Shown when the island is shared with another activity. The platform
                // is dropped here: the one thing worth the space is how long is left.
                TargetCapsule(
                    name: "",
                    target: context.state.targetDate,
                    isStale: context.isStale,
                    showsName: false,
                    size: .compact
                )
            }
            .widgetURL(TrainActivityLinks.journey(context.attributes))
            .keylineTint(JourneyPalette.target)
        }
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
