import SwiftUI

/// Set by the split layout: a tap on a row calls it to open that journey in the
/// detail column. Absent in the stack layout, where a row pushes the journey itself.
private struct SelectTrainKey: EnvironmentKey {
    static let defaultValue: ((Train) -> Void)? = nil
}

extension EnvironmentValues {
    var selectTrain: ((Train) -> Void)? {
        get { self[SelectTrainKey.self] }
        set { self[SelectTrainKey.self] = newValue }
    }
}

/// Set by the split layout: the deeper colour behind the list in its own column, so
/// it reads apart from the journey on the right. Absent otherwise, and the lists keep
/// the system's grouped background.
private struct SidebarBackgroundKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var sidebarBackground: Color? {
        get { self[SidebarBackgroundKey.self] }
        set { self[SidebarBackgroundKey.self] = newValue }
    }
}

/// Set by the main screen on a device with the Duo's bezel strip: the journey screen
/// then puts its buttons in a row of spacer-separated capsules there.
private struct HasBezelStripKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hasBezelStrip: Bool {
        get { self[HasBezelStripKey.self] }
        set { self[HasBezelStripKey.self] = newValue }
    }
}

/// A list row's card: the system's grouped fill, with a soft gray over it for the
/// journey open in the right-hand column. Only the split layout marks a selection.
func trainRowBackground(isSelected: Bool) -> some View {
    ZStack {
        Color(.secondarySystemGroupedBackground)
        if isSelected { Color(.tertiarySystemFill) }
    }
}
