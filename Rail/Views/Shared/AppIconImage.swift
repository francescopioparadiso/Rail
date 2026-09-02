import SwiftUI
import UIKit

enum AppIconImage {
    /// The bundled app icon, for share previews. Asset-catalog app icons aren't
    /// addressable by name, so this goes through the generated Info.plist entry.
    static let image: Image? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last,
              let icon = UIImage(named: name)
        else { return nil }
        return Image(uiImage: icon)
    }()
}
