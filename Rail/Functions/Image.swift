import SwiftUI
import SwiftData
import PhotosUI
import Vision

enum image_status: CaseIterable {
    case empty
    case saved
    case error
    
    var icon: String {
        switch self {
        case .empty:
            return "qrcode.viewfinder"
        case .saved:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .empty:
            return Color.secondary
        case .saved:
            return Color.green
        case .error:
            return Color.red
        }
    }
}


// crop code from image data
func cropCodeFromImage(originalData: Data) async -> Data? {
    /// 1. Load the original image
    guard let uiImage = UIImage(data: originalData) else { return nil }
    
    /// 2. Fix Orientation so Vision sees what we see
    guard let fixedImage = fixOrientation(img: uiImage),
          let cgImage = fixedImage.cgImage else {
        return originalData
    }
    
    return await withCheckedContinuation { continuation in
        let request = VNDetectBarcodesRequest { request, error in
            guard let results = request.results as? [VNBarcodeObservation],
                  let code = results.first(where: { $0.symbology == .aztec || $0.symbology == .qr }) else {
                /// Fallback: If no code found, return original
                continuation.resume(returning: originalData)
                return
            }
            
            /// 3. Calculate Crop Rect
            let boundingBox = code.boundingBox
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            
            let x = boundingBox.minX * width
            let y = (1.0 - boundingBox.maxY) * height /// Flip Y for CoreGraphics
            let w = boundingBox.width * width
            let h = boundingBox.height * height
            
            /// Add a little padding (10%) so we don't cut off the edges of the code
            let padding: CGFloat = 0.1
            let paddedRect = CGRect(
                x: max(0, x - (w * padding)),
                y: max(0, y - (h * padding)),
                width: min(width, w * (1 + 2 * padding)),
                height: min(height, h * (1 + 2 * padding))
            )
            
            if let croppedCG = cgImage.cropping(to: paddedRect) {
                /// 4. Enhance the image
                let enhancedData = enhanceImageQuality(cgImage: croppedCG)
                continuation.resume(returning: enhancedData)
            } else {
                continuation.resume(returning: originalData)
            }
        }
        
        /// Use accurate revision no. 1
        request.revision = VNDetectBarcodesRequestRevision1
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    }
}

// enhance image quality
private func enhanceImageQuality(cgImage: CGImage) -> Data {
    let ciImage = CIImage(cgImage: cgImage)
    let context = CIContext()
    
    // A. Convert to Black & White (Removes color noise/tint)
    let monoFilter = CIFilter.photoEffectMono()
    monoFilter.inputImage = ciImage
    var outputImage = monoFilter.outputImage ?? ciImage
    
    // B. Boost Contrast (Makes the code "pop" against background)
    let contrastFilter = CIFilter.colorControls()
    contrastFilter.inputImage = outputImage
    contrastFilter.contrast = 1.5 // Significant boost
    contrastFilter.brightness = 0.0
    outputImage = contrastFilter.outputImage ?? outputImage
    
    // C. Sharpen (Defines the edges of the pixels)
    let sharpenFilter = CIFilter.unsharpMask()
    sharpenFilter.inputImage = outputImage
    sharpenFilter.radius = 2.5
    sharpenFilter.intensity = 0.8
    outputImage = sharpenFilter.outputImage ?? outputImage
    
    // D. Smart Upscale (If image is too small, upscale it using Lanczos for smoothness)
    if outputImage.extent.width < 500 {
        let scale = 500 / outputImage.extent.width
        let upscaleFilter = CIFilter.lanczosScaleTransform()
        upscaleFilter.inputImage = outputImage
        upscaleFilter.scale = Float(scale)
        upscaleFilter.aspectRatio = 1.0
        outputImage = upscaleFilter.outputImage ?? outputImage
    }
    
    // Render to Data
    if let resultCG = context.createCGImage(outputImage, from: outputImage.extent) {
        let resultUI = UIImage(cgImage: resultCG)
        // Use PNG to avoid JPEG artifacts on the sharp edges of the QR code
        return resultUI.pngData() ?? Data()
    }
    
    // Fallback to simple conversion if filters fail
    return UIImage(cgImage: cgImage).pngData() ?? Data()
}

// orientation fix
func fixOrientation(img: UIImage) -> UIImage? {
    if img.imageOrientation == .up { return img }
    UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
    img.draw(in: CGRect(origin: .zero, size: img.size))
    let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalizedImage
}
