import SwiftUI

let appFontDesign: Font.Design = .rounded
let appBackgroundColor = Color(.secondarySystemBackground)

extension View {
    /// Applies a modifier only when a condition holds.
    ///
    /// Branching like this re-identifies the view when the condition flips, so use
    /// it only for a condition fixed for the life of the view — a `let` passed in
    /// at construction, not a piece of state.
    @ViewBuilder
    func applyingIf<Modified: View>(_ condition: Bool, _ transform: (Self) -> Modified) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
