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
