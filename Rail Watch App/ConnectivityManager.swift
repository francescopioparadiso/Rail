import Foundation
import WatchConnectivity
import ClockKit // Only needed for WatchOS to reload complications

class ConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = ConnectivityManager()
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - WCSessionDelegate Standard Methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("⚡️ WCSession activated: \(activationState.rawValue)")
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    
    // MARK: - iOS: Sending Data
    func sendTrainUpdate(isTraveling: Bool, trainNumber: String, delay: Int, nextStop: String) {
        // 1. Usa WCSession.isSupported() (classe), non .default (istanza)
        guard WCSession.isSupported() && WCSession.default.activationState == .activated else { return }
        
        let context: [String: Any] = [
            "isTraveling": isTraveling,
            "trainNumber": trainNumber,
            "delay": delay,
            "nextStop": nextStop,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            try WCSession.default.updateApplicationContext(context)
            print("📤 Context sent to Watch: \(trainNumber), Delay: \(delay)")
        } catch {
            print("❌ Error sending context: \(error)")
        }
    }
    #endif
    
    #if os(watchOS)
    // MARK: - WatchOS: Receiving Data
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            print("⌚️ Watch received context")
            
            // 1. Save data to UserDefaults (so your ComplicationController can read it)
            let defaults = UserDefaults.standard
            if let isTraveling = applicationContext["isTraveling"] as? Bool {
                defaults.set(isTraveling, forKey: "isTraveling")
            }
            if let trainNumber = applicationContext["trainNumber"] as? String {
                defaults.set(trainNumber, forKey: "trainNumber")
            }
            if let delay = applicationContext["delay"] as? Int {
                defaults.set(delay, forKey: "delay")
            }
            if let nextStop = applicationContext["nextStop"] as? String {
                defaults.set(nextStop, forKey: "nextStop")
            }
            
            // 2. Reload Complications immediately
            let server = CLKComplicationServer.sharedInstance()
            for complication in server.activeComplications ?? [] {
                server.reloadTimeline(for: complication)
            }
        }
    }
    #endif
}
