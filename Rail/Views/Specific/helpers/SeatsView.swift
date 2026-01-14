import SwiftUI
import SwiftData
import PhotosUI
import Vision

enum row_focus {
    case carriage
    case number
    case name
}
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

struct SeatsView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var all_seats: [Seat]
    let train: Train
    let seats: [Seat]
    
    // focus variables
    @FocusState private var row_focus: row_focus?
    
    // image variables
    @State private var image_status: image_status = .empty
    @State private var picked_image: PhotosPickerItem? = nil
    @State private var qr_image_data: Data? = nil
    @State private var seat_to_view: Seat? = nil
    @State private var show_ticket_view: Bool = false
    
    // new seat variables
    @State private var show_adding_row: Bool = false
    @State private var new_name: String = ""
    @State private var new_carriage: String = ""
    @State private var new_number: String = ""
    
    // computed variables
    var name_placeholder: String {
        var name_count: [String: Int] = [:]
        for seat in all_seats {
            name_count[seat.name, default: 0] += 1
        }
        return name_count.max(by: { $0.value < $1.value })?.key ?? ""
    }
    
    // button variables
    var topLeft_icon: String {
        switch show_adding_row {
            case true:
                return "arrow.uturn.left"
            
            case false:
                return "xmark"
        }
    }
    var topLeft_action: () -> Void {
        switch show_adding_row {
            case true:
                return {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    
                    show_adding_row = false
                    image_status = .empty
                    
                    new_name = ""
                    new_carriage = ""
                    new_number = ""
                    picked_image = nil
                    qr_image_data = nil
                }
            
            case false:
                return {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                }
        }
    }
    var topRight_icon: String {
        switch show_adding_row {
            case true:
                return "checkmark"
            
            case false:
                return "plus"
        }
    }
    var topRight_action: () -> Void {
        switch show_adding_row {
            case true:
                return {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    
                    add_seat()
                    
                    show_adding_row = false
                    image_status = .empty
                    
                    new_name = ""
                    new_carriage = ""
                    new_number = ""
                    picked_image = nil
                    qr_image_data = nil
                }
            
            case false:
                return {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    row_focus = .name
                    show_adding_row = true
                }
        }
    }
    var topRight_shoudBeActive: Bool {
        if !show_adding_row {
            return true
            
        } else if !new_name.isEmpty && ((!new_number.isEmpty && !new_carriage.isEmpty) || (picked_image != nil)) {
            return true
            
        } else {
            return false
        }
    }
    
    // MARK: - main content
    var body: some View {
        NavigationStack {
            List {
                // MARK: - empty view
                if !show_adding_row && seats.isEmpty {
                    ContentUnavailableView("No seats added",
                                           systemImage: "airplaneseat",
                                           description: Text("Add a new seat by tapping the above button."))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(Color.secondary)
                    .fontDesign(appFontDesign)
                }
                
                // MARK: - add seat row
                if show_adding_row {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Francesco", text: $new_name)
                                .font(.headline)
                                .keyboardType(.default)
                                .focused($row_focus, equals: .name)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                .onSubmit {
                                    row_focus = .carriage
                                }
                                .onChange(of: new_name) { _, new_value in
                                    if new_value.count >= 15 {
                                        new_name = String(new_value.prefix(15))
                                    }
                                }
                            
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "train.side.rear.car")
                                    TextField("22", text: $new_carriage)
                                        .keyboardType(.numbersAndPunctuation)
                                        .focused($row_focus, equals: .carriage)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        .onSubmit {
                                            row_focus = .number
                                        }
                                        .onChange(of: new_carriage) { _, new_value in
                                            if new_value.count >= 2 {
                                                row_focus = .number
                                                new_carriage = String(new_value.prefix(2))
                                            }
                                        }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: 64)
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "carseat.left.fill")
                                    TextField("15A", text: $new_number)
                                        .keyboardType(.numbersAndPunctuation)
                                        .focused($row_focus, equals: .number)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        .onChange(of: new_number) { _, new_value in
                                            if new_value.count >= 3 {
                                                new_number = String(new_value.prefix(3))
                                            }
                                        }
                                }
                            }
                            .font(.body)
                            .fontDesign(appFontDesign)
                        }
                        
                        Spacer()
                        
                        PhotosPicker(selection: $picked_image, matching: .images) {
                            Image(systemName: image_status.icon)
                                .font(.title)
                                .foregroundStyle(image_status.color)
                                .contentTransition(
                                    .symbolEffect(.replace.magic(fallback: .downUp.byLayer),
                                                  options: .nonRepeating)
                                )
                        }
                        .onChange(of: picked_image) { _, newItem in
                            process_image(newItem: newItem)
                        }
                    }
                    .foregroundStyle(Color.secondary)
                }
                
                // MARK: - existing seats list
                ForEach(seats, id: \.id) { seat in
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(seat.name)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if !seat.carriage.isEmpty && !seat.number.isEmpty {
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: "train.side.rear.car")
                                        Text(seat.carriage)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: 64)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: "carseat.left.fill")
                                        Text(seat.number)
                                    }
                                }
                                .font(.body)
                            }
                        }
                        .fontDesign(appFontDesign)
                        
                        Spacer()
                        
                        // Fixed condition: check if image data is not empty
                        if let _ = seat.image {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                seat_to_view = seat
                                show_ticket_view = true
                            } label: {
                                Image(systemName: "qrcode")
                                    .font(.title)
                            }
                        }
                    }
                }
                .onDelete(perform: delete_seat)
            }
            .navigationTitle("Your Seats")
            .toolbar {
                // MARK: - top left button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        topLeft_action()
                    } label: {
                        Image(systemName: topLeft_icon)
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }
                
                // MARK: - top right button
                ToolbarItem(placement: .navigationBarTrailing) {
                    switch topRight_shoudBeActive {
                    case true:
                        Button {
                            topRight_action()
                        } label: {
                            Image(systemName: topRight_icon)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                        }
                        .buttonStyle(.glassProminent)
                        
                    case false:
                        Button {
                            topRight_action()
                        } label: {
                            Image(systemName: topRight_icon)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                        }
                        .disabled(true)
                    }
                }
            }
            .sheet(isPresented: $show_ticket_view) {
                TicketView(seat: seat_to_view ?? Seat(id: UUID(), trainID: UUID(), name: "", carriage: "", number: "", image: Data()))
            }
            .onAppear {
                new_name = name_placeholder
            }
        }
    }
    
    // MARK: - functions
    private func add_seat() {
        guard !new_name.isEmpty else { return }
        
        let new_carriage_formatted: String = {
            if !new_carriage.isEmpty {
                let new_carriage_clean = new_carriage.filter { $0.isNumber }
                return String(new_carriage_clean.prefix(2))
            } else {
                return ""
            }
        }()
        
        let new_number_formatted: String = {
            if !new_number.isEmpty {
                let new_number_clean = new_number.filter { $0.isLetter || $0.isNumber }
                return String(new_number_clean.prefix(3)).uppercased()
            } else {
                return ""
            }
        }()
        
        let new_name_formatted: String = {
            let new_name_clean = new_name.filter { $0.isLetter || $0.isNumber }
            return new_name_clean.prefix(1).uppercased() + new_name_clean.dropFirst().lowercased()
        }()
        
        // ✅ CHANGED: Handle optional data
        let imageData = qr_image_data
        
        let seat_to_add = Seat(
            id: UUID(),
            trainID: train.id,
            name: new_name_formatted,
            carriage: new_carriage_formatted,
            number: new_number_formatted,
            image: imageData // Pass the optional data directly
        )
        modelContext.insert(seat_to_add)
    }
    
    private func delete_seat(at offsets: IndexSet) {
        for index in offsets {
            let seat = seats[index]
            modelContext.delete(seat)
        }
    }
    
    private func process_image(newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        
        image_status = .empty
        qr_image_data = nil
        
        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    
                    // ✅ CHANGED: Use the robust cropping logic
                    let processedData = await cropCodeFromImage(originalData: data)
                    
                    await MainActor.run {
                        qr_image_data = processedData
                        image_status = .saved
                    }
                    
                } else {
                    await MainActor.run { image_status = .error }
                }
            } catch {
                await MainActor.run { image_status = .error }
            }
            
            if await MainActor.run(body: { image_status }) == .error {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { image_status = .empty }
            }
        }
    }
}

// MARK: - Image Processing Extension
extension SeatsView {
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
                    let enhancedData = self.enhanceImageQuality(cgImage: croppedCG)
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
}
