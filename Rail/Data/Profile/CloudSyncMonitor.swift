import Foundation
import CoreData
import Observation

/// Watches SwiftData's CloudKit sync, so the app can say when it is downloading
/// from iCloud. iOS has no call to start or force a download; this only reports what
/// the system does.
@MainActor @Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    /// True while a first-seen import is still running after a moment: a quick
    /// import on an ordinary launch never shows it.
    private(set) var showsFetchAlert = false

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var isImporting = false
    @ObservationIgnored private var hasAnnounced = false

    /// Starts listening; call once at launch.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import else { return }
            let finished = event.endDate != nil
            Task { @MainActor in
                CloudSyncMonitor.shared.importChanged(finished: finished)
            }
        }
    }

    /// Binding target for the alert: closing it by hand just hides it for this launch.
    func dismissAlert() { showsFetchAlert = false }

    private func importChanged(finished: Bool) {
        isImporting = !finished
        if finished {
            showsFetchAlert = false
        } else if !hasAnnounced {
            hasAnnounced = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if isImporting { showsFetchAlert = true }
            }
        }
    }
}
