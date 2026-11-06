import SwiftUI
import UIKit
import ActivityKit

/// The email behind Settings → About → Send a Report: an empty Notes block for the
/// user to describe the problem, then everything about the device and the app that
/// helps to reproduce it.
enum ReportEmail {
    static let address = "francesco@francescoparadiso.com"
    static let subject = "Rail - report"

    /// A `mailto:` link, which opens whichever mail app the user has set as default.
    @MainActor
    static var url: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    @MainActor
    private static var body: String {
        """


        ---------- Notes ----------




        ---------- Info ----------
        \(info.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        """
    }

    // MARK: - Info

    @MainActor
    private static var info: [(String, String)] {
        let bundle = Bundle.main
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        let locale = Locale.current
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        return [
            ("App", "\(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Rail") \(version) (\(build))"),
            ("Bundle ID", bundle.bundleIdentifier ?? "?"),
            ("Build type", isDebug ? "Debug" : (isTestFlight ? "TestFlight" : "App Store")),
            ("Device", "\(modelIdentifier) (\(device.model))"),
            ("Device type", device.userInterfaceIdiom.label),
            ("System", "\(device.systemName) \(device.systemVersion) (\(osBuild))"),
            ("Processors", "\(process.activeProcessorCount) of \(process.processorCount)"),
            ("Memory", ByteCountFormatter.string(fromByteCount: Int64(process.physicalMemory), countStyle: .memory)),
            ("Free storage", freeStorage),
            ("Screen", screen),
            ("Battery", battery),
            ("Low Power Mode", process.isLowPowerModeEnabled ? "On" : "Off"),
            ("Thermal state", process.thermalState.label),
            ("Language", Locale.preferredLanguages.first ?? "?"),
            ("Region", locale.region?.identifier ?? "?"),
            ("Time zone", TimeZone.current.identifier),
            ("Appearance", UITraitCollection.current.userInterfaceStyle == .dark ? "Dark" : "Light"),
            ("Text size", UIApplication.shared.preferredContentSizeCategory.rawValue),
            ("iCloud", FileManager.default.ubiquityIdentityToken != nil ? "Signed in" : "Not signed in"),
            ("Live Activities", ActivityAuthorizationInfo().areActivitiesEnabled ? "Enabled" : "Disabled"),
            ("Date", Date().formatted(.iso8601))
        ]
    }

    /// "iPhone17,1"; on a simulator, the model it stands in for.
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// "23A344": the exact system build, which the version number alone doesn't give.
    private static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build)
    }

    private static var freeStorage: String {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage,
              let total = values?.volumeTotalCapacity else { return "?" }
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        return "\(format(free)) of \(format(Int64(total)))"
    }

    @MainActor
    private static var screen: String {
        let screen = UIScreen.main
        let size = screen.nativeBounds.size
        return "\(Int(size.width))×\(Int(size.height)) @\(Int(screen.nativeScale))x"
    }

    @MainActor
    private static var battery: String {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        guard device.batteryLevel >= 0 else { return "Unknown" }
        return "\(Int(device.batteryLevel * 100))% (\(device.batteryState.label))"
    }

    private static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}

private extension UIUserInterfaceIdiom {
    var label: String {
        switch self {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .vision: "Apple Vision"
        case .mac: "Mac"
        default: "Other"
        }
    }
}

private extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

private extension UIDevice.BatteryState {
    var label: String {
        switch self {
        case .unplugged: "Unplugged"
        case .charging: "Charging"
        case .full: "Full"
        default: "Unknown"
        }
    }
}
