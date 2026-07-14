import Foundation
import WidgetKit

/// Reloads widget timelines from a background task so saves and sheet
/// dismissals aren't blocked by the widget refresh round trip.
nonisolated func reload_widget_timelines() {
    Task.detached(priority: .background) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
