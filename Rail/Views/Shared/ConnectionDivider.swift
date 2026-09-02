import SwiftUI

/// A dashed rule with the layover time sitting in the gap.
///
/// Shared by the Choose Train solution rows and the Today/Past journey lists.
struct ConnectionDivider: View {
    // MARK: - Properties

    let minutes: Int

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(journeyDuration(minutes: minutes))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .contentTransition(.numericText(value: Double(minutes)))
                .animation(.snappy, value: minutes)
            line
        }
    }

    // MARK: - Subviews

    private var line: some View {
        DashedLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
