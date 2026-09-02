import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit

struct PassFormSheet: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @State private var previewedDocument: PassDocumentPreview?
    @Environment(\.modelContext) private var modelContext

    let passToEdit: Pass?
    let onSave: () -> Void

    @State private var name: String
    @State private var start_date: Date
    @State private var expiry_date: Date
    @State private var price: String
    @State private var pickedImage: PhotosPickerItem?
    @State private var qrImageData: Data?
    @State private var previewImage: UIImage?
    @State private var imageStatus: ImageStatus = .empty
    @State private var isProcessingImage = false
    @State private var isEditing: Bool

    init(passToEdit: Pass?, onSave: @escaping () -> Void) {
        self.passToEdit = passToEdit
        self.onSave = onSave

        _name = State(initialValue: passToEdit?.name ?? String(localized: "Weekly"))
        _start_date = State(initialValue: passToEdit?.start_date ?? Date())
        _expiry_date = State(initialValue: passToEdit?.expiry_date ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _price = State(initialValue: passToEdit?.price ?? "")
        _qrImageData = State(initialValue: passToEdit?.image)
        _imageStatus = State(initialValue: passToEdit?.image != nil ? .saved : .empty)
        _isEditing = State(initialValue: passToEdit == nil)

        if let data = passToEdit?.image, let image = UIImage(data: data) {
            _previewImage = State(initialValue: image)
        }
    }

    // MARK: - Computed

    private var isFormEditable: Bool {
        passToEdit == nil || isEditing
    }

    private var canSave: Bool {
        isFormEditable && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && qrImageData != nil && !isProcessingImage
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Pass Information")) {
                    LabeledContent(String(localized: "Name")) {
                        if isFormEditable {
                            TextField(String(localized: "Weekly"), text: $name)
                                .multilineTextAlignment(.trailing)
                                .fontDesign(appFontDesign)
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

                    LabeledContent(String(localized: "Price")) {
                        if isFormEditable {
                            TextField(String(localized: "e.g. 50,00 €"), text: $price)
                                .multilineTextAlignment(.trailing)
                                .fontDesign(appFontDesign)
                        } else {
                            Text(price)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isFormEditable {
                        DatePicker(String(localized: "Start Date"), selection: $start_date, displayedComponents: .date)
                            .fontDesign(appFontDesign)

                        DatePicker(String(localized: "Expiration Date"), selection: $expiry_date, displayedComponents: .date)
                            .fontDesign(appFontDesign)
                            .onChange(of: expiry_date) { _, newDate in
                                let days = Calendar.current.dateComponents([.day], from: start_date, to: newDate).day ?? 0
                                let newTitle: String
                                if days <= 14 {
                                    newTitle = String(localized: "Weekly")
                                } else if days <= 60 {
                                    newTitle = String(localized: "Monthly")
                                } else {
                                    newTitle = String(localized: "Annual")
                                }

                                if name != newTitle {
                                    withAnimation(.snappy) {
                                        name = newTitle
                                    }
                                }
                            }
                    } else {
                        LabeledContent(String(localized: "Start Date")) {
                            Text(start_date.formatted(.dateTime.day().month().year()))
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent(String(localized: "Expiration Date")) {
                            Text(expiry_date.formatted(.dateTime.day().month().year()))
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

                if let pass = passToEdit, let pdf = pass.pdf, !pdf.isEmpty {
                    Section("Document") {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pass.documentFilename)
                                    .lineLimit(1)
                                Text(pdf.count.formatted(.byteCount(style: .file)))
                                    .font(.footnote)
                            }

                            Spacer(minLength: 12)

                            // sharing lives in the preview, which is one tap away
                            Image(systemName: "chevron.right")
                                .font(.footnote).fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.primary)
                        // tapping the row reads the document; the share icon keeps its own target
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticFeedback.tap()
                            previewedDocument = PassDocumentPreview(data: pdf, filename: pass.documentFilename)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(appFontDesign)
            .navigationTitle(passToEdit == nil ? String(localized: "New Pass") : String(localized: "Edit Pass"))
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
                    if passToEdit != nil && !isEditing {
                        Button(String(localized: "Edit")) {
                            HapticFeedback.confirm()
                            withAnimation(.snappy) {
                                isEditing = true
                            }
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if passToEdit == nil || isEditing {
                        Button {
                            savePass()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                    }
                }
            }
        }
        .background(appBackgroundColor)
        .sheet(item: $previewedDocument) { document in
            PassDocumentView(data: document.data, filename: document.filename)
        }
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
                    .frame(maxWidth: 200, maxHeight: 200)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func savePass() {
        HapticFeedback.impactHeavy()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pass = passToEdit {
            pass.name = trimmedName
            pass.start_date = start_date
            pass.expiry_date = expiry_date
            pass.price = price
            pass.image = qrImageData
        } else {
            let newPass = Pass(
                id: UUID(),
                name: trimmedName,
                start_date: start_date,
                expiry_date: expiry_date,
                is_principal: false,
                price: price,
                image: qrImageData
            )
            modelContext.insert(newPass)
        }

        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        onSave()
        if passToEdit == nil {
            dismiss()
        } else {
            withAnimation {
                isEditing = false
            }
        }
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
