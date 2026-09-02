import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func blendedToolbarItemBackground() -> some ToolbarContent {
        sharedBackgroundVisibility(.hidden)
    }
}
