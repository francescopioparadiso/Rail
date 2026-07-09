import SwiftUI
import Foundation
import CoreLocation
import Observation

@Observable
class SpeedManager: NSObject, CLLocationManagerDelegate {
    var displayedSpeed: Int = 0
    var permissionStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    private var speedReadings: [Double] = []
    private var updateTimer: Timer?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startMonitoring() {
        locationManager.startUpdatingLocation()
        
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateDisplayedSpeed()
        }
    }
    
    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
        speedReadings.removeAll()
        displayedSpeed = 0
    }
    
    // MARK: - Internal Logic
    private func updateDisplayedSpeed() {
        guard !speedReadings.isEmpty else {
            Task { @MainActor in
                withAnimation(.snappy) {
                    self.displayedSpeed = 0
                }
            }
            return
        }
        
        let sum = speedReadings.reduce(0, +)
        let averageSpeed = sum / Double(speedReadings.count)
        
        Task { @MainActor in
            let newSpeed = Int(round(averageSpeed))
            
            if newSpeed != self.displayedSpeed {
                self.displayedSpeed = newSpeed
            }
        }
        
        speedReadings.removeAll()
    }
    
    // MARK: - Delegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if location.speed >= 0 {
            let speedInKmh = location.speed * 3.6
            speedReadings.append(speedInKmh)
        } else {
            speedReadings.append(0)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.permissionStatus = manager.authorizationStatus
    }
}

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
            .fontDesign(app_font_design)
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
