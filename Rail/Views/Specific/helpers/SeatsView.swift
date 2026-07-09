import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit
import StoreKit

struct SeatsView: View {
    // MARK: - variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var request_review
    @Environment(\.modelContext) private var modelContext
    @Query private var all_seats: [Seat]
    @Query private var profiles: [UserProfile]

    let train: Train
    let seats: [Seat]
    let initialSeatID: UUID?

    @State private var searchText = ""
    @State private var seat_form_presentation: SeatFormPresentation? = nil

    private enum SeatFormPresentation: Identifiable {
        case new
        case edit(Seat)

        var id: String {
            switch self {
            case .new:
                return "new"
            case .edit(let seat):
                return seat.id.uuidString
            }
        }

        var seatToEdit: Seat? {
            if case .edit(let seat) = self { return seat }
            return nil
        }
    }

    private var name_placeholder: String {
        var name_count: [String: Int] = [:]
        for seat in all_seats {
            name_count[seat.name, default: 0] += 1
        }
        return name_count.max(by: { $0.value < $1.value })?.key ?? ""
    }

    private var sortedSeats: [Seat] {
        seats.sorted { lhs, rhs in
            if lhs.carriage != rhs.carriage {
                return lhs.carriage.localizedStandardCompare(rhs.carriage) == .orderedAscending
            } else if lhs.number != rhs.number {
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedAscending
            } else {
                return lhs.name < rhs.name
            }
        }
    }

    private var filteredSeats: [Seat] {
        sortedSeats.filter { matches($0, searchText: searchText) }
    }

    // MARK: - main content
    var body: some View {
        NavigationStack {
            Group {
                if seats.isEmpty {
                    ContentUnavailableView(
                        "No seats added",
                        systemImage: "airplaneseat",
                        description: Text("Add a new seat using the button below.")
                    )
                    .foregroundStyle(.secondary)
                    .fontDesign(app_font_design)
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredSeats.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .fontDesign(app_font_design)
                } else {
                    List {
                        Section {
                            ForEach(filteredSeats) { seat in
                                seatRow(seat: seat)
                            }
                            .onDelete { offsets in
                                delete_seats(at: offsets, from: filteredSeats)
                            }
                        } header: {
                            Text("\(filteredSeats.count) \(filteredSeats.count == 1 ? "seat" : "seats")")
                                .contentTransition(.numericText(value: Double(filteredSeats.count)))
                                .animation(.snappy, value: filteredSeats.count)
                        }
                        .fontDesign(app_font_design)
                    }
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Your Seats")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        seat_form_presentation = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .searchable(text: $searchText, prompt: "Search seats")
            .sheet(item: $seat_form_presentation) { presentation in
                SeatFormSheet(
                    train: train,
                    seatToEdit: presentation.seatToEdit,
                    namePlaceholder: name_placeholder,
                    isFirstSeatForTrain: seats.isEmpty && presentation.seatToEdit == nil,
                    accountName: profiles.first?.name ?? ""
                )
                .presentationDetents([.large])
            }
            .onAppear {
                ReviewManager.shared.requestReviewIfAppropriate(action: request_review)

                if let initialID = initialSeatID, let seat = seats.first(where: { $0.id == initialID }) {
                    seat_form_presentation = .edit(seat)
                }
            }
        }
        .background(app_background_color.ignoresSafeArea())
    }

    private func matches(_ seat: Seat, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableFields = [
            seat.name,
            seat.carriage,
            seat.number,
        ]

        return searchableFields.contains { $0.lowercased().contains(query) }
    }

    @ViewBuilder
    private func seatRow(seat: Seat) -> some View {
        HStack(spacing: 12) {
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
                    .foregroundStyle(.secondary)
                }
            }
            .fontDesign(app_font_design)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            seat_form_presentation = .edit(seat)
        }
    }

    private func delete_seats(at offsets: IndexSet, from list: [Seat]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct SeatFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let train: Train
    let seatToEdit: Seat?
    let namePlaceholder: String
    let isFirstSeatForTrain: Bool
    let accountName: String

    private enum FocusField: Hashable {
        case name
        case carriage
        case number
    }

    @FocusState private var focused_field: FocusField?
    @State private var name: String
    @State private var carriage: String
    @State private var number: String
    @State private var picked_image: PhotosPickerItem?
    @State private var qr_image_data: Data?
    @State private var preview_image: UIImage?
    @State private var image_status: image_status = .empty
    @State private var is_processing_image = false
    @State private var is_editing: Bool

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
        _qr_image_data = State(initialValue: seatToEdit?.image)
        _image_status = State(initialValue: seatToEdit?.image != nil ? .saved : .empty)
        _is_editing = State(initialValue: seatToEdit == nil)

        if let data = seatToEdit?.image, let image = UIImage(data: data) {
            _preview_image = State(initialValue: image)
        }
    }

    private var is_form_editable: Bool {
        seatToEdit == nil || is_editing
    }

    private var name_was_autofilled: Bool {
        guard seatToEdit == nil, isFirstSeatForTrain else { return false }
        return !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var can_save: Bool {
        guard is_form_editable, !is_processing_image, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let hasSeatDetails = !formattedCarriage.isEmpty && !formattedNumber.isEmpty
        return hasSeatDetails || qr_image_data != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Seat Information")) {
                    LabeledContent(String(localized: "Name")) {
                        if is_form_editable {
                            TextField(namePlaceholder.isEmpty ? "Francesco" : namePlaceholder, text: $name)
                                .multilineTextAlignment(.trailing)
                                .fontDesign(app_font_design)
                                .focused($focused_field, equals: .name)
                                .submitLabel(.next)
                                .onSubmit {
                                    focused_field = .carriage
                                }
                                .onChange(of: name) { _, new_value in
                                    if new_value.count >= 15 {
                                        name = String(new_value.prefix(15))
                                    }
                                }
                        } else {
                            Text(name)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent(String(localized: "Carriage")) {
                        if is_form_editable {
                            TextField("22", text: $carriage)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .fontDesign(app_font_design)
                                .focused($focused_field, equals: .carriage)
                                .submitLabel(.next)
                                .onSubmit {
                                    focused_field = .number
                                }
                                .onChange(of: carriage) { _, new_value in
                                    if new_value.count >= 2 {
                                        carriage = String(new_value.prefix(2))
                                        focused_field = .number
                                    }
                                }
                        } else {
                            Text(carriage.isEmpty ? "—" : carriage)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent(String(localized: "Seat")) {
                        if is_form_editable {
                            TextField("15A", text: $number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .fontDesign(app_font_design)
                                .focused($focused_field, equals: .number)
                                .submitLabel(.done)
                                .onSubmit {
                                    focused_field = nil
                                }
                                .onChange(of: number) { _, new_value in
                                    if new_value.count >= 3 {
                                        number = String(new_value.prefix(3))
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
                        if is_form_editable {
                            PhotosPicker(selection: $picked_image, matching: .images) {
                                qrCodePreview
                            }
                            .buttonStyle(.plain)
                            .onChange(of: picked_image) { _, newItem in
                                process_image(newItem: newItem)
                            }
                        } else {
                            qrCodePreview
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("QR Code")
                } footer: {
                    if is_form_editable {
                        if image_status == .error {
                            Text("Couldn't detect a QR code in that photo. Try another image.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Tap the photo area to choose an image or tap it again to change it.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(app_font_design)
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
                    if seatToEdit != nil && !is_editing {
                        Button(String(localized: "Edit")) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.snappy) {
                                is_editing = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focused_field = .name
                            }
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if seatToEdit == nil || is_editing {
                        Button {
                            save_seat()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!can_save)
                    }
                }
            }
        }
        .onAppear {
            guard seatToEdit == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused_field = name_was_autofilled ? .carriage : .name
            }
        }
        .background(app_background_color)
    }

    @ViewBuilder
    private var qrCodePreview: some View {
        Group {
            if is_processing_image {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Processing photo…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if let preview_image {
                Image(uiImage: preview_image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private func save_seat() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        if let seat = seatToEdit {
            seat.name = formattedName
            seat.carriage = formattedCarriage
            seat.number = formattedNumber
            seat.image = qr_image_data
        } else {
            let new_seat = Seat(
                id: UUID(),
                trainID: train.id,
                name: formattedName,
                carriage: formattedCarriage,
                number: formattedNumber,
                image: qr_image_data
            )
            modelContext.insert(new_seat)
        }

        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    private func process_image(newItem: PhotosPickerItem?) {
        guard let newItem else { return }

        is_processing_image = true
        image_status = .empty
        qr_image_data = nil
        preview_image = nil

        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    if let originalImage = UIImage(data: data) {
                        await MainActor.run {
                            preview_image = originalImage
                        }
                    }

                    let processedData = await cropCodeFromImage(originalData: data)

                    await MainActor.run {
                        is_processing_image = false
                        qr_image_data = processedData
                        if let processedData, let processedImage = UIImage(data: processedData) {
                            preview_image = processedImage
                            image_status = .saved
                        } else {
                            image_status = .error
                        }
                    }
                } else {
                    await MainActor.run {
                        is_processing_image = false
                        image_status = .error
                    }
                }
            } catch {
                await MainActor.run {
                    is_processing_image = false
                    image_status = .error
                }
            }

            if await MainActor.run(body: { image_status }) == .error {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { image_status = .empty }
            }
        }
    }
}

// MARK: - previews
#Preview("Populated List") {
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    let mockTrain = Train(
        id: UUID(),
        logo: "trenitalia",
        number: "9607",
        identifier: "FR9607",
        provider: "trenitalia",
        last_update_time: Date(),
        delay: 0,
        direction: "Napoli Centrale",
        issue: ""
    )

    let seat1 = Seat(id: UUID(), trainID: mockTrain.id, name: "Pierpaolo", carriage: "1", number: "2D", image: UIImage(named: "sample_code")?.pngData())
    let seat2 = Seat(id: UUID(), trainID: mockTrain.id, name: "Davide", carriage: "1", number: "7B", image: UIImage(named: "sample_code")?.pngData())
    let seat3 = Seat(id: UUID(), trainID: mockTrain.id, name: "Andrea", carriage: "1", number: "8C", image: UIImage(named: "sample_code")?.pngData())

    container.mainContext.insert(mockTrain)
    container.mainContext.insert(seat1)
    container.mainContext.insert(seat2)
    container.mainContext.insert(seat3)

    return SeatsView(train: mockTrain, seats: [seat1, seat2, seat3], initialSeatID: nil)
        .modelContainer(container)
        .environment(\.locale, Locale(identifier: "it"))
}

#Preview("Empty State") {
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    let mockTrain = Train(
        id: UUID(),
        logo: "italo",
        number: "9923",
        identifier: "IT9923",
        provider: "italo",
        last_update_time: Date(),
        delay: 5,
        direction: "Milano Centrale",
        issue: ""
    )

    container.mainContext.insert(mockTrain)

    return SeatsView(train: mockTrain, seats: [], initialSeatID: nil)
        .modelContainer(container)
}
