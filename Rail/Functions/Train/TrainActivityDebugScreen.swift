#if DEBUG
import SwiftUI

/// The Live Activity's Lock Screen view, drawn inside the app.
///
/// A Live Activity that gets something wrong shows a blank rectangle and tells you
/// nothing else, so this puts the same view somewhere it can be looked at, stepped
/// through and screenshotted. Reached with `-rail-preview-activity` on the command
/// line; debug builds only.
struct TrainActivityDebugScreen: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let label: String
        let journey: TrainJourney
    }

    private let samples: [Sample] = [
        Sample(label: "not departed", journey: TrainActivitySample.notDeparted),
        Sample(label: "en route", journey: TrainActivitySample.enRoute),
        Sample(label: "next is arrival", journey: TrainActivitySample.nextIsArrival),
        Sample(label: "no platform", journey: TrainActivitySample.noPlatform)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(samples) { sample in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: sample.label)
                            .font(.caption).foregroundStyle(.secondary)

                        if let state = TrainActivityState.resolve(sample.journey) {
                            TrainActivityLockScreen(
                                attributes: TrainActivitySample.withSeat,
                                state: state,
                                isStale: false
                            )
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                        } else {
                            Text(verbatim: "resolve returned nil")
                                .foregroundStyle(.red)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "stale (Now)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let state = TrainActivityState.resolve(TrainActivitySample.enRoute) {
                        TrainActivityLockScreen(
                            attributes: TrainActivitySample.withoutSeat,
                            state: state,
                            isStale: true
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            .padding()
        }
    }
}
#endif
