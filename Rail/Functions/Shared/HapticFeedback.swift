import UIKit

enum HapticFeedback {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func confirm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func impactHeavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
