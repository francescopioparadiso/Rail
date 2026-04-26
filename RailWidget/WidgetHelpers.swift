import SwiftUI

// MARK: - Shared Constants
let widgetFontDesign: Font.Design = .rounded

// MARK: - Shared Helpers
func scaleImage(data: Data?, to maxWidth: CGFloat) -> Data? {
    guard let data = data, let uiImage = UIImage(data: data) else { return nil }
    
    let currentSize = uiImage.size
    guard currentSize.width > maxWidth else { return data }
    
    let scale = maxWidth / currentSize.width
    let newHeight = currentSize.height * scale
    let newSize = CGSize(width: maxWidth, height: newHeight)
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    uiImage.draw(in: CGRect(origin: .zero, size: newSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return scaledImage?.pngData()
}
