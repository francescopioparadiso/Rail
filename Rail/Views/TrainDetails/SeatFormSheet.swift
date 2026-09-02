import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit

struct SeatFormSheet: View {
    // MARK: - Types

    private enum FocusField: Hashable {
        case name
        case carriage
        case number
    }

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let train: Train
    let seatToEdit: Seat?
    let namePlaceholder: String
    let isFirstSeatForTrain: Bool
    let accountName: String

    @FocusState private var focusedField: FocusField?
    @State private var name: String
    @State private var carriage: String
    @State private var number: String
    @State private var pickedImage: PhotosPickerItem?
    @State private var qrImageData: Data?
    @State private var previewImage: UIImage?
    @State private var imageStatus: ImageStatus = .empty
    @State private var isProcessingImage = false
    @State private var isEditing: Bool

    init(train: Train, seatToEdit: Seat?, namePlaceholder: String, isFirstSeatForTrain: Bool, accountName: String) {
        self.train = train
        self.seatToEdit = seatToEdit
        self.namePlaceholder = namePlaceholder
        self.isFirstSeatForTrain = isFirstSeatForTrain
        self.accountName = accountName

        let initialName: String = {
            if let seatToEdit {
                return seatToEdit.name
            }
            if isFirstSeatForTrain {
                let trimmedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedAccountName.isEmpty {
                    return trimmedAccountName
                }
            }
            return namePlaceholder
        }()

        _name = State(initialValue: initialName)
        _carriage = State(initialValue: seatToEdit?.carriage ?? "")
        _number = State(initialValue: seatToEdit?.number ?? "")
        _qrImageData = State(initialValue: seatToEdit?.image)
        _imageStatus = State(initialValue: seatToEdit?.image != nil ? .saved : .empty)
        _isEditing = State(initialValue: seatToEdit == nil)

        if let data = seatToEdit?.image, let image = UIImage(data: data) {
            _previewImage = State(initialValue: image)
        }
    }

    // MARK: - Computed

    private var isFormEditable: Bool {
        seatToEdit == nil || isEditing
    }

    private var nameWasAutofilled: Bool {
        guard seatToEdit == nil, isFirstSeatForTrain else { return false }
        return !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        guard isFormEditable, !isProcessingImage, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let hasSeatDetails = !formattedCarriage.isEmpty && !formattedNumber.isEmpty
        return hasSeatDetails || qrImageData != nil
    }

    private var formattedCarriage: String {
        let clean = carriage.filter { $0.isNumber }
        return String(clean.prefix(2))
    }

    private var formattedNumber: String {
        let clean = number.filter { $0.isLetter || $0.isNumber }
        return String(clean.prefix(3)).uppercased()
    }

    private var formattedName: String {
        let clean = name.filter { $0.isLetter || $0.isNumber }
        guard let first = clean.first else { return "" }
        return String(first).uppercased() + clean.dropFirst().lowercased()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Seat Information")) {
                    LabeledContent(String(localized: "Name")) {
                        if isFormEditable {
                            TextField(namePlaceholder.isEmpty ? "Francesco" : namePlaceholder, text: $name)
                                .multilineTextAlignment(.trailing)
                                .fontDesign(appFontDesign)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .carriage
                                }
                                .onChange(of: name) { _, newValue in
                                    if newValue.count >= 15 {
                                        name = String(newValue.prefix(15))
                                    }
                                }
                        } else {
                            Text(name)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent(String(localized: "Carriage")) {
                        if isFormEditable {
                            TextField("22", text: $carriage)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .fontDesign(appFontDesign)
                                .focused($focusedField, equals: .carriage)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .number
                                }
                                .onChange(of: carriage) { _, newValue in
                                    if newValue.count >= 2 {
                                        carriage = String(newValue.prefix(2))
                                        focusedField = .number
                                    }
                                }
                        } else {
                            Text(carriage.isEmpty ? "—" : carriage)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent(String(localized: "Seat")) {
                        if isFormEditable {
                            TextField("15A", text: $number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .fontDesign(appFontDesign)
                                .focused($focusedField, equals: .number)
                                .submitLabel(.done)
                                .onSubmit {
                                    focusedField = nil
                                }
                                .onChange(of: number) { _, newValue in
                                    if newValue.count >= 3 {
                                        number = String(newValue.prefix(3))
                                    }
                                }
                        } else {
                            Text(number.isEmpty ? "—" : number)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Group {
                        if isFormEditable {
                            PhotosPicker(selection: $pickedImage, matching: .images) {
                                qrCodePreview
                            }
                            .buttonStyle(.plain)
                            .onChange(of: pickedImage) { _, newItem in
                                processImage(newItem: newItem)
                            }
                        } else {
                            qrCodePreview
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("QR Code")
                } footer: {
                    if isFormEditable {
                        if imageStatus == .error {
                            Text("Couldn't detect a QR code in that photo. Try another image.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Tap the photo area to choose an image or tap it again to change it.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(appFontDesign)
            .navigationTitle(seatToEdit == nil ? String(localized: "New Seat") : String(localized: "Edit Seat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if seatToEdit != nil && !isEditing {
                        Button(String(localized: "Edit")) {
                            HapticFeedback.confirm()
                            withAnimation(.snappy) {
                                isEditing = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .name
                            }
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if seatToEdit == nil || isEditing {
                        Button {
                            saveSeat()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear {
            guard seatToEdit == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = nameWasAutofilled ? .carriage : .name
            }
        }
        .background(appBackgroundColor)
    }

    // MARK: - Subviews

    private var qrCodePreview: some View {
        Group {
            if isProcessingImage {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Processing photo…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    // follows the list row's own curve inset by the padding above,
                    // instead of a fixed radius that never lined up with it
                    .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.tertiary)

                    Text("Add Photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func saveSeat() {
        HapticFeedback.impactHeavy()

        if let seat = seatToEdit {
            seat.name = formattedName
            seat.carriage = formattedCarriage
            seat.number = formattedNumber
            seat.image = qrImageData
        } else {
            let newSeat = Seat(
                id: UUID(),
                trainID: train.id,
                name: formattedName,
                carriage: formattedCarriage,
                number: formattedNumber,
                image: qrImageData
            )
            modelContext.insert(newSeat)
        }

        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    private func processImage(newItem: PhotosPickerItem?) {
        guard let newItem else { return }

        isProcessingImage = true
        imageStatus = .empty
        qrImageData = nil
        previewImage = nil

        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    if let originalImage = UIImage(data: data) {
                        await MainActor.run {
                            previewImage = originalImage
                        }
                    }

                    let processedData = await cropCodeFromImage(originalData: data)

                    await MainActor.run {
                        isProcessingImage = false
                        qrImageData = processedData
                        if let processedData, let processedImage = UIImage(data: processedData) {
                            previewImage = processedImage
                            imageStatus = .saved
                        } else {
                            imageStatus = .error
                        }
                    }
                } else {
                    await MainActor.run {
                        isProcessingImage = false
                        imageStatus = .error
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessingImage = false
                    imageStatus = .error
                }
            }

            if await MainActor.run(body: { imageStatus }) == .error {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { imageStatus = .empty }
            }
        }
    }
}
