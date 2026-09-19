import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Countdown

/// The time left to the stop the journey is aimed at.
///
/// It has to keep running with Rail closed, so it is never a string this app
/// computes: the system is handed the date and ticks it down itself. When the target
/// arrives the activity goes stale — a flip the system also makes on its own — and
/// the countdown becomes "Now".
struct CountdownText: View {

    /// How the remaining time is written.
    ///
    /// `.units` is the one we want — "1h 25m", "12m", a figure that changes once a
    /// minute rather than once a second. It is also the one with the least settled
    /// behaviour inside a Live Activity: the sign of `durationOffset(to:)` for a
    /// future date, and whether the system really does redraw it every minute, are
    /// both worth watching on a device.
    ///
    /// `.timer` is the fallback and behaves identically everywhere, at the cost of
    /// counting seconds too. Switching is this one line.
    enum Style { case units, timer }
    static let style: Style = .units

    let target: Date
    let isStale: Bool
    var isCompact: Bool = false

    var body: some View {
        Group {
            if isStale {
                Text("Now")
                    .foregroundStyle(JourneyPalette.target)
            } else {
                switch Self.style {
                case .units:
                    Text(
                        TimeDataSource<Date>.durationOffset(to: target),
                        format: .units(
                            allowed: [.hours, .minutes],
                            width: .narrow,
                            fractionalPart: .hide(rounded: .down)
                        )
                    )
                case .timer:
                    Text(timerInterval: Date()...max(target, Date().addingTimeInterval(1)), countsDown: true)
                }
            }
        }
        .fontDesign(journeyFontDesign)
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: true))
    }
}

// MARK: - Lock Screen

/// The whole journey, in three bands: who and where you are sitting, the stops, and
/// what is left to wait.
struct TrainActivityView: View {
    let context: ActivityViewContext<TrainActivityAttributes>

    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var state: TrainActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(spacing: 10) {
            header
            stations
            footer
        }
        .padding(14)
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
            row(state.departure, role: .departure, isDepartureSide: true)

            if let intermediate = state.intermediate {
                row(intermediate, role: .intermediate, isDepartureSide: false)
            }

            row(state.arrival, role: .arrival, isDepartureSide: false)
        }
        .font(.subheadline)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            JourneyCapsule(
                foreground: context.isStale ? JourneyPalette.target : .primary,
                fillsWidth: true
            ) {
                CountdownText(target: state.targetDate, isStale: context.isStale)
            }

            PlatformCapsule(
                platform: state.platform,
                isDeparture: state.targetRole != .arrival
            )
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(
        _ row: TrainActivityAttributes.ContentState.Row,
        role: TrainActivityAttributes.ContentState.TargetRole,
        isDepartureSide: Bool
    ) -> some View {
        let isTarget = state.targetRole == role && row.name == state.targetName

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
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        TrainLogo(logo: context.attributes.logo, height: 18)
                        Text(context.attributes.number)
                            .font(.subheadline).fontWeight(.semibold)
                            .fontDesign(journeyFontDesign)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let seat = TrainActivityLinks.seat(context.attributes) {
                        Link(destination: seat) {
                            SeatCapsule(label: context.attributes.seatLabel, compact: true)
                        }
                    } else {
                        SeatCapsule(label: context.attributes.seatLabel, compact: true)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    expandedStations(context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        JourneyCapsule(
                            foreground: context.isStale ? JourneyPalette.target : .primary,
                            fillsWidth: true,
                            compact: true
                        ) {
                            CountdownText(target: context.state.targetDate, isStale: context.isStale)
                        }

                        PlatformCapsule(
                            platform: context.state.platform,
                            isDeparture: context.state.targetRole != .arrival,
                            compact: true
                        )
                    }
                }
            } compactLeading: {
                PlatformCapsule(
                    platform: context.state.platform,
                    isDeparture: context.state.targetRole != .arrival,
                    compact: true
                )
            } compactTrailing: {
                CountdownText(target: context.state.targetDate, isStale: context.isStale, isCompact: true)
                    .font(.caption)
            } minimal: {
                // Shown when the island is shared with another activity, so it is
                // only ever the one thing worth a glance.
                CountdownText(target: context.state.targetDate, isStale: context.isStale, isCompact: true)
                    .font(.caption2)
            }
            .widgetURL(TrainActivityLinks.journey(context.attributes))
            .keylineTint(JourneyPalette.target)
        }
    }

    /// The same stations as the Lock Screen, tightened to what the island allows.
    @ViewBuilder
    private func expandedStations(_ context: ActivityViewContext<TrainActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            islandRow(context.state.departure, isTarget: context.state.targetRole == .departure)

            if let intermediate = context.state.intermediate {
                islandRow(intermediate, isTarget: context.state.targetRole == .intermediate)
            }

            islandRow(context.state.arrival, isTarget: context.state.targetRole == .arrival)
        }
        .font(.caption)
    }

    private func islandRow(
        _ row: TrainActivityAttributes.ContentState.Row,
        isTarget: Bool
    ) -> some View {
        HStack {
            Text(row.name)
                .fontDesign(journeyFontDesign)
                .foregroundStyle(isTarget ? JourneyPalette.target : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(row.effective, format: .dateTime.hour().minute())
                .fontDesign(journeyFontDesign)
                .foregroundStyle(isTarget ? JourneyPalette.target : Color.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Lock Screen", as: .content, using: TrainActivitySample.withSeat) {
    TrainLiveActivity()
} contentStates: {
    // Not departed: two rows, boarding station blue.
    TrainActivitySample.state(TrainActivitySample.notDeparted)
    // Running, with a stop to come between the two ends: three rows.
    TrainActivitySample.state(TrainActivitySample.enRoute)
    // A leg inside a longer service, boarding and alighting mid-route.
    TrainActivitySample.state(TrainActivitySample.midRoute)
    // Nothing left before the end of the journey: back to two rows.
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
