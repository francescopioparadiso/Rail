import SwiftUI
import SwiftData
import PhotosUI
import Vision

enum seat_row_focus {
    case carriage
    case number
    case name
}

struct SeatsView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var color_scheme
    @Environment(\.requestReview) var request_review
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var all_seats: [Seat]
    let train: Train
    let seats: [Seat]
    
    // focus variables
    @FocusState private var seat_row_focus: seat_row_focus?
    
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
    private var name_placeholder: String {
        var name_count: [String: Int] = [:]
        for seat in all_seats {
            name_count[seat.name, default: 0] += 1
        }
        return name_count.max(by: { $0.value < $1.value })?.key ?? ""
    }
    
    // button variables
    private var topLeft_icon: String {
        switch show_adding_row {
            case true:
                return "arrow.uturn.left"
            
            case false:
                return "xmark"
        }
    }
    private var topRight_icon: String {
        switch show_adding_row {
            case true:
                return "checkmark"
            
            case false:
                return "plus"
        }
    }
    private var addNew_icon: String {
        if seat_row_focus == nil {
            return "plus"
        } else {
            return "checkmark"
        }
    }
    
    private var addNew_text: String {
        if seat_row_focus == nil {
            return NSLocalizedString("Add", comment: "")
        } else {
            return NSLocalizedString("Save", comment: "")
        }
    }
    
    private var topLeft_action: () -> Void {
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
    private var addNew_action: () -> Void {
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
                    seat_row_focus = .name
                    show_adding_row = true
                }
        }
    }
    
    private var addNew_shouldBeActive: Bool {
        if seat_row_focus == nil {
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
            ZStack(alignment: .bottom) {
                VStack {
                    if !show_adding_row && seats.isEmpty {
                        // MARK: - empty view
                        ContentUnavailableView("No seats added",
                                               systemImage: "airplaneseat",
                                               description: Text("Add a new seat by tapping the below button."))
                        .foregroundColor(Color.secondary)
                        .fontDesign(app_font_design)
                        .padding(.bottom, 80)
                    } else {
                        // MARK: - add seat row
                        List {
                            // adding row
                            if show_adding_row {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("Francesco", text: $new_name)
                                            .font(.headline)
                                            .keyboardType(.default)
                                            .focused($seat_row_focus, equals: .name)
                                            .onTapGesture {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            }
                                            .onSubmit {
                                                seat_row_focus = .carriage
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
                                                    .focused($seat_row_focus, equals: .carriage)
                                                    .onTapGesture {
                                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    }
                                                    .onSubmit {
                                                        seat_row_focus = .number
                                                    }
                                                    .onChange(of: new_carriage) { _, new_value in
                                                        if new_value.count >= 2 {
                                                            seat_row_focus = .number
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
                                                    .focused($seat_row_focus, equals: .number)
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
                                        .fontDesign(app_font_design)
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
                            
                            // existing seats list
                            ForEach(seats.sorted(by: { lhs, rhs in
                                if lhs.carriage != rhs.carriage {
                                    return lhs.carriage.localizedStandardCompare(rhs.carriage) == .orderedAscending
                                    
                                } else if lhs.number != rhs.number {
                                    return lhs.number.localizedStandardCompare(rhs.number) == .orderedAscending
                                    
                                } else {
                                    return lhs.name < rhs.name
                                }
                            })) { seat in
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
                                    .fontDesign(app_font_design)
                                    
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
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 80)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                
                HStack(spacing: 8) {
                    if seat_row_focus != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            show_adding_row = false
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .padding(.horizontal).padding(.vertical, seat_row_focus == nil ? 24 : 16)
                        }
                        .font(.title3)
                        .fontWeight(.medium)
                        .fontDesign(app_font_design)
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(Color.accentColor)
                        .tint(Color.accentColor.opacity(0.15))
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
                    
                    Button {
                        addNew_action()
                    } label: {
                        HStack {
                            Image(systemName: addNew_icon)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            
                            Text(addNew_text)
                                .contentTransition(.numericText(value: Double(addNew_text.hashValue)))
                                .animation(.snappy, value: addNew_text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, seat_row_focus == nil ? 24 : 16)
                    }
                    .font(.title3)
                    .fontWeight(.medium)
                    .fontDesign(app_font_design)
                    .buttonStyle(.glassProminent)
                    .disabled(!addNew_shouldBeActive)
                    .foregroundStyle(addNew_shouldBeActive ? Color.accentColor : Color.primary)
                    .tint(addNew_shouldBeActive ? Color.accentColor.opacity(0.15) : color_scheme == .dark ? Color.black.opacity(0.1) : Color.clear)
                }
                .padding()
            }
            .ignoresSafeArea(edges: seat_row_focus == nil ? .bottom : [])
            .navigationTitle("Your Seats")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        topLeft_action()
                    } label: {
                        Image(systemName: "xmark")
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }
            }
            .sheet(isPresented: $show_ticket_view) {
                TicketView(seat: seat_to_view ?? Seat(id: UUID(), trainID: UUID(), name: "", carriage: "", number: "", image: Data()))
            }
            .onAppear {
                new_name = name_placeholder
                ReviewManager.shared.requestReviewIfAppropriate(action: request_review)
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

// MARK: - previews
#Preview("Populated List") {
    // memory container
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // mock data
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
    let seat4 = Seat(id: UUID(), trainID: mockTrain.id, name: "Marco", carriage: "1", number: "10C", image: UIImage(named: "sample_code")?.pngData())
    let seat5 = Seat(id: UUID(), trainID: mockTrain.id, name: "Luca", carriage: "1", number: "10D", image: UIImage(named: "sample_code")?.pngData())
    let seat6 = Seat(id: UUID(), trainID: mockTrain.id, name: "Riccardo", carriage: "1", number: "11A", image: UIImage(named: "sample_code")?.pngData())
    let seat7 = Seat(id: UUID(), trainID: mockTrain.id, name: "Fabio", carriage: "1", number: "14B", image: UIImage(named: "sample_code")?.pngData())
    
    container.mainContext.insert(mockTrain)
    container.mainContext.insert(seat1)
    container.mainContext.insert(seat2)
    container.mainContext.insert(seat3)
    container.mainContext.insert(seat4)
    container.mainContext.insert(seat5)
    container.mainContext.insert(seat6)
    container.mainContext.insert(seat7)
    
    // view
    return SeatsView(train: mockTrain, seats: [seat1, seat2, seat3, seat4, seat5, seat6, seat7])
        .modelContainer(container)
        .environment(\.locale, Locale(identifier: "it"))
}

#Preview("Empty State") {
    // memory container
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // mock data
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
    
    // view
    return SeatsView(train: mockTrain, seats: [])
        .modelContainer(container)
}
