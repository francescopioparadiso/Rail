import SwiftUI

/// A sweeping highlight for content that is still loading.
///
/// Deliberately prominent. An earlier version used `.plusLighter` with
/// `Color.primary`, which is black in light mode and therefore invisible on a
/// white row; this pulses the whole row and sweeps a grey band across the text,
/// so the effect reads on either appearance.
struct Shimmer: ViewModifier {
    var isActive: Bool

    private let cycle = 1.3

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycle) / cycle
                // 0.40 → 0.85 → 0.40 across one cycle
                let pulse = 0.40 + 0.45 * (0.5 - 0.5 * cos(2 * .pi * phase))
                let sweep = phase * 2.4 - 0.7

                content
                    .opacity(pulse)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: max(0, min(1, sweep - 0.3))),
                                .init(color: Color.secondary.opacity(0.45), location: max(0, min(1, sweep))),
                                .init(color: .clear, location: max(0, min(1, sweep + 0.3))),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(content)
                        .allowsHitTesting(false)
                    }
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(_ isActive: Bool) -> some View { modifier(Shimmer(isActive: isActive)) }
}
