import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Activity view

/// What the system actually asks for, which is the view above wearing the Lock
/// Screen's own chrome.
struct TrainActivityView: View {
    let context: ActivityViewContext<TrainActivityAttributes>

    var body: some View {
        TrainActivityLockScreen(
            attributes: context.attributes,
            state: context.state,
            isStale: context.isStale
        )
        // Low enough to keep the wallpaper showing through, which is what makes the
        // whole thing read as glass rather than as a card.
        .activityBackgroundTint(Color.black.opacity(0.12))
        .activitySystemActionForegroundColor(JourneyPalette.target)
        .widgetURL(TrainActivityLinks.journey(context.attributes))
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
                // In the bottom region rather than the centre: this is the one
                // that has drawn reliably here, and the centre competes with the
                // leading and trailing slots even when they are empty.
                DynamicIslandExpandedRegion(.bottom) {
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
                    .padding(.vertical, 4)
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
