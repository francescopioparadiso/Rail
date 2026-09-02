import Foundation
import CoreImage
import UIKit

/// Reads the string inside a QR image and writes it back out again.
///
/// Sharing the payload rather than the PNG keeps a shared journey's link short:
/// a ticket code is a few dozen characters where the image is several kilobytes.
enum QRCodePayload {
    private static let context = CIContext()
    private static let cache = NSCache<NSNumber, NSString>()

    /// The text encoded in a QR image, if it holds one.
    static func decode(from data: Data) -> String? {
        let key = NSNumber(value: data.hashValue)
        if let hit = cache.object(forKey: key) { return hit as String }

        guard let image = CIImage(data: data) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let found = (detector?.features(in: image) as? [CIQRCodeFeature])?
            .compactMap(\.messageString)
            .first { !$0.isEmpty }

        if let found { cache.setObject(found as NSString, forKey: key) }
        return found
    }

    /// Renders a QR image for the given text.
    static func image(from payload: String, scale: CGFloat = 10) -> Data? {
        guard !payload.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}
