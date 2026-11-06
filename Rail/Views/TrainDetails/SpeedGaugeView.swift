import SwiftUI

struct SpeedGaugeView: View {
    // MARK: - Properties

    /// In the Duo's strip the system only takes a button whose label is a plain image
    /// from the first moment, as the profile photo is. There the gauge is drawn into an
    /// image on every change of speed — never an empty placeholder first, which would
    /// have the system leave the button out of the strip.
    var iconOnly = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var speedManager = SpeedManager()

    // MARK: - Body

    var body: some View {
        Button {} label: {
            if iconOnly {
                stripImage
            } else {
                gauge
                    .scaleEffect(0.6)
                    .frame(width: 25, height: 25)
            }
        }
        .onAppear {
            speedManager.requestPermission()
            speedManager.startMonitoring()
        }
        .onDisappear {
            speedManager.stopMonitoring()
        }
    }

    private var gauge: some View {
        Gauge(value: Double(speedManager.displayedSpeed), in: 0...300) {
            Text("kph")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        } currentValueLabel: {
            Text("\(speedManager.displayedSpeed)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText(value: Double(speedManager.displayedSpeed)))
                .animation(.snappy, value: speedManager.displayedSpeed)
        }
        .fontDesign(appFontDesign)
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.green, .yellow, .red]))
    }

    /// The same gauge, redrawn by hand: a `Gauge` does not survive being rendered
    /// into an image outside a widget — its ring comes out clipped.
    @ViewBuilder
    private var stripImage: some View {
        let renderer = ImageRenderer(
            content: SpeedGaugeDrawing(speed: speedManager.displayedSpeed)
                .frame(width: 44, height: 44)
                .environment(\.colorScheme, colorScheme)
        )
        let _ = renderer.scale = displayScale
        if let image = renderer.uiImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "speedometer")
        }
    }
}

/// The round speed gauge: a gradient ring open at the bottom with a marker at the
/// current speed, the number inside and "kph" underneath.
private struct SpeedGaugeDrawing: View {
    let speed: Int

    private let top = 300.0
    /// The ring spans 270°, from the lower left round to the lower right.
    private let start = 135.0
    private let sweep = 270.0

    var body: some View {
        let fraction = min(max(Double(speed) / top, 0), 1)
        let angle = Angle.degrees(start + sweep * fraction)

        ZStack {
            Circle()
                .trim(from: 0, to: sweep / 360)
                .rotation(.degrees(start))
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .red],
                        center: .center,
                        startAngle: .degrees(start),
                        endAngle: .degrees(start + sweep)
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .padding(3)

            // Marker: a dot on the ring, ringed in the background colour to stand out.
            GeometryReader { proxy in
                let radius = proxy.size.width / 2 - 3
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    .position(
                        x: proxy.size.width / 2 + radius * cos(angle.radians),
                        y: proxy.size.height / 2 + radius * sin(angle.radians)
                    )
            }

            VStack(spacing: -2) {
                Text("\(speed)")
                    .font(.system(size: 14, weight: .bold, design: appFontDesign))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 28)
                    .foregroundStyle(Color.primary)
                Text("kph")
                    .font(.system(size: 10, design: appFontDesign))
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
