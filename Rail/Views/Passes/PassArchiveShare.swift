import SwiftUI
import UIKit

/// A built zip, identified so it can drive a `.sheet(item:)`.
struct PassArchiveFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet. `ShareLink` needs its item up front, but the zip
/// only exists once the user asks for it, so this is presented after building.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish?() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
