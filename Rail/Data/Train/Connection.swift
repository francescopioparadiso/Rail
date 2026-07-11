import SwiftUI

enum ConnectionStatus {
    case highRisk
    case tight
    case relaxed
    case comfortable

    init(minutes: Int) {
        if minutes < 20 { self = .highRisk }
        else if minutes < 40 { self = .tight }
        else if minutes < 60 { self = .relaxed }
        else { self = .comfortable }
    }

    var text: String {
        switch self {
        case .highRisk: return String(localized: "Hurry up! High risk")
        case .tight: return String(localized: "Tight connection")
        case .relaxed: return String(localized: "Take your time")
        case .comfortable: return String(localized: "Time to relax")
        }
    }

    var icon: String {
        switch self {
        case .highRisk: return "figure.run"
        case .tight: return "exclamationmark.triangle.fill"
        case .relaxed: return "clock.fill"
        case .comfortable: return "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .highRisk: return .red
        case .tight: return .orange
        case .relaxed: return .yellow
        case .comfortable: return .green
        }
    }
}
