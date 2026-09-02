import SwiftUI

struct SpeedGaugeView: View {
    @State private var speedManager = SpeedManager()

    var body: some View {
        Button {} label: {
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
            .scaleEffect(0.6)
            .frame(width: 25, height: 25)
        }
        .onAppear {
            speedManager.requestPermission()
            speedManager.startMonitoring()
        }
        .onDisappear {
            speedManager.stopMonitoring()
        }
    }
}
