import Foundation

/// Somewhere for a link that arrives while the app is already running to wait.
///
/// A widget's `widgetURL` reaches `onOpenURL` on its own, but a tapped notification
/// arrives through the notification centre's delegate, which has no view to route
/// from. Parking the same URL here lets it land in the one place that already knows
/// how to read it, rather than growing a second way in.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pending: URL?

    private init() {}

    func open(trainID: UUID) {
        pending = URL(string: "railapp://view-train?trainID=\(trainID.uuidString)")
    }
}
