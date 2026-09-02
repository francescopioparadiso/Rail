import Foundation
import CoreImage
import UIKit
import Vision

/// Reads the code inside a ticket image and writes it back out again.
///
/// Sharing the payload rather than the PNG keeps a shared journey's link short:
/// a ticket code is a few dozen characters where the image is several kilobytes.
///
/// Both symbologies the app accepts are handled. That matters: Trenitalia prints
/// **Aztec**, not QR, so reading with a QR-only detector found nothing on a real
/// ticket and re-rendering as QR would have produced a code the gate cannot scan.
enum QRCodePayload {
    private static let context = CIContext()
    private static let cache = NSCache<NSNumber, Decoded>()

    /// A ticket code: its text plus which symbology it was drawn in, so the
    /// image can be rebuilt exactly as it was.
    final class Decoded: NSObject {
        let text: String
        let symbology: Symbology

        init(text: String, symbology: Symbology) {
            self.text = text
            self.symbology = symbology
        }
    }

    enum Symbology: Int, Codable, Sendable {
        case qr = 0
        case aztec = 1

        var generatorName: String {
            switch self {
            case .qr: "CIQRCodeGenerator"
            case .aztec: "CIAztecCodeGenerator"
            }
        }
    }

    // MARK: - Reading

    /// The code held in a ticket image, if it holds one.
    static func read(from data: Data) -> Decoded? {
        let key = NSNumber(value: data.hashValue)
        if let hit = cache.object(forKey: key) { return hit }

        guard let image = UIImage(data: data),
              let cgImage = fixOrientation(img: image)?.cgImage else { return nil }

        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision3
        request.symbologies = [.qr, .aztec]
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        guard let match = (request.results)?.first(where: {
            ($0.payloadStringValue?.isEmpty == false) && ($0.symbology == .qr || $0.symbology == .aztec)
        }), let text = match.payloadStringValue else { return nil }

        let decoded = Decoded(text: text, symbology: match.symbology == .aztec ? .aztec : .qr)
        cache.setObject(decoded, forKey: key)
        return decoded
    }

    /// The text encoded in a ticket image, if it holds one.
    static func decode(from data: Data) -> String? {
        read(from: data)?.text
    }

    // MARK: - Writing

    /// Renders a ticket code for the given text, in the symbology it came from.
    static func image(from payload: String, symbology: Symbology = .qr, scale: CGFloat = 10) -> Data? {
        guard !payload.isEmpty,
              let filter = CIFilter(name: symbology.generatorName) else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        if symbology == .qr {
            filter.setValue("M", forKey: "inputCorrectionLevel")
        }
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }

    // MARK: - Sharing fallback

    /// A copy of the image small enough to travel inside a link, for tickets whose
    /// code cannot be read back — a photographed ticket, or a damaged code. Shrunk
    /// to the smallest size that still scans and written as 1-bit-ish grayscale PNG.
    static func compressedForSharing(_ data: Data, maxDimension: CGFloat = 360) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let shrunk = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return shrunk.pngData()
    }
}
