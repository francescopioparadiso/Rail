import SwiftUI
import SwiftData
import PhotosUI
import Vision
import WidgetKit

enum pass_row_focus {
    case name
    case expiry_date
    case image
}

struct AddPassView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var passes: [Pass]
    private var sorted_passes: [Pass] {
        passes.sorted { $0.expiry_date > $1.expiry_date }
    }
    private var principal_pass: Pass? {
        passes.first(where: { $0.is_principal })
    }
    
    // focus variables
    @FocusState private var pass_row_focus: pass_row_focus?
    
    // new pass variables
    @State private var show_adding_row: Bool = false
    @State private var new_name: String = ""
    @State private var new_expiry_date: Date = Date()
    
    // image variables
    @State private var image_status: image_status = .empty
    @State private var picked_image: PhotosPickerItem? = nil
    @State private var qr_image_data: Data? = nil
    @State private var pass_to_view: Pass? = nil
    @State private var show_pass_view: Bool = false
    
    // button variables
    private var addNew_icon: String {
        if show_adding_row == false {
            return "plus"
        } else {
            return "checkmark"
        }
    }
    private var addNew_text: String {
        if show_adding_row == false {
            return NSLocalizedString("Add", comment: "")
        } else {
            return NSLocalizedString("Save", comment: "")
        }
    }
    private var addNew_shouldBeActive: Bool {
        if pass_row_focus == nil {
            return true
        } else if !new_name.isEmpty && picked_image != nil {
            return true
        } else {
            return false
        }
    }
    private var addNew_action: () -> Void {
        switch show_adding_row {
            case true:
                return {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    
                    save_pass()
                }
            
            case false:
                return {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    
                    pass_row_focus = .name
                    new_name = "Settimanale"
                    
                    show_adding_row = true
                }
        }
    }
    
    // MARK: - main view
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack {
                    if passes.isEmpty && !show_adding_row {
                        // MARK: - empty view
                        ContentUnavailableView("No passes added",
                                               systemImage: "ticket.fill",
                                               description: Text("Add a new passes using the button below."))
                        .foregroundColor(Color.secondary)
                        .fontDesign(app_font_design)
                        .padding(.bottom, 80)
                        
                    } else {
                        // MARK: - populated view
                        List {
                            // principal pass info
                            if !passes.isEmpty {
                                if principal_pass != nil {
                                    VStack(spacing: 16) {
                                        // code
                                        if let imageData = principal_pass?.image, let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .interpolation(.none)
                                                .scaledToFit()
                                                .padding()
                                                .background(Color.white)
                                                .cornerRadius(16)
                                        } else {
                                            ContentUnavailableView("No Code", systemImage: "qrcode.viewfinder")
                                        }
                                        
                                        // info
                                        VStack(spacing: 8) {
                                            Text(principal_pass?.name ?? "")
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                                .contentTransition(.numericText(value: Double((principal_pass?.name.hashValue ?? 0))))
                                                .animation(.snappy, value: principal_pass?.name)
                                            
                                            HStack(spacing: 8) {
                                                Image(systemName: "calendar")
                                                
                                                Text(principal_pass?.expiry_date ?? Date(), format: .dateTime.day().month().year())
                                                    .contentTransition(.numericText(value: Double((principal_pass?.expiry_date.hashValue ?? 0))))
                                                    .animation(.snappy, value: principal_pass?.expiry_date)
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .padding(.vertical, 8).padding(.horizontal, 12)
                                            .background(Color.secondary.opacity(0.15))
                                            .cornerRadius(16)
                                        }
                                        .fontDesign(app_font_design)
                                        .foregroundStyle(Color.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .listRowSeparator(.hidden)
                                    .padding(8)
                                    .padding(.bottom, 48)
                                    
                                } else {
                                    ContentUnavailableView("Principal pass",
                                                           systemImage: "ticket.fill",
                                                           description: Text("Add your principal passes here by swiping to the right on a pass in the list."))
                                    .fontDesign(app_font_design)
                                    .foregroundColor(Color.secondary)
                                    .listRowSeparator(.hidden)
                                    .frame(height: 470)
                                }
                            }
                            
                            // adding row
                            if show_adding_row {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("Settimanale", text: $new_name)
                                            .font(.headline)
                                            .keyboardType(.default)
                                            .focused($pass_row_focus, equals: .name)
                                            .onChange(of: new_name) { _, new_value in
                                                if new_value.count >= 15 {
                                                    new_name = String(new_value.prefix(15))
                                                }
                                            }
                                        
                                        HStack {
                                            DatePicker("Expiry Date", selection: $new_expiry_date, displayedComponents: .date)
                                                .labelsHidden()
                                                .datePickerStyle(.compact)
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
                                .foregroundStyle(Color.primary)
                            }
                            
                            // existing pass list
                            ForEach(Array(sorted_passes.enumerated()), id: \.element.id) { index, pass in
                                let time_remaining: String = {
                                    if pass.expiry_date < Date() {
                                        let dateString = pass.expiry_date.formatted(.dateTime.day().month().year())
                                        return String(localized: "Expired on \(dateString)")
                                    }
                                    
                                    let totalDays = Calendar.current.dateComponents([.day], from: Date(), to: pass.expiry_date).day ?? 0
                                    if totalDays == 0 { return String(localized: "Expires today") }
                                    if totalDays == 1 { return String(localized: "Expires tomorrow") }
                                    
                                    return String(localized: "Expires in \(totalDays) days")
                                }()
                                var expiry_date_color: Color {
                                    if pass.expiry_date >= Date() {
                                        return Color.green
                                    } else {
                                        return Color.red
                                    }
                                }
                                
                                HStack {
                                    if pass.is_principal {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.orange)
                                            .font(.title)
                                            .padding(.trailing, 4)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pass.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        HStack {
                                            Text(pass.expiry_date >= Date() ? "Active" : "Expired")
                                                .font(.subheadline).fontDesign(app_font_design)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .foregroundStyle(expiry_date_color)
                                                .background(expiry_date_color.opacity(0.15))
                                                .shadow(color: expiry_date_color, radius: 20)
                                                .cornerRadius(16)
                                            
                                            Text(time_remaining)
                                                .font(.subheadline)
                                                .foregroundStyle(expiry_date_color)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let _ = pass.image {
                                        Button {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            pass_to_view = pass
                                            show_pass_view = true
                                        } label: {
                                            Image(systemName: "qrcode")
                                                .font(.title)
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                        withAnimation(.spring()) {
                                            for pass in passes {
                                                pass.is_principal = false
                                            }
                                            pass.is_principal = true
                                            
                                            try? modelContext.save()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                WidgetCenter.shared.reloadAllTimelines()
                                            }
                                        }
                                    } label: {
                                        Label("Set Principal", systemImage: "star.fill")
                                    }
                                    .tint(.orange)
                                }
                            }
                            .onDelete(perform: delete_pass)
                        }
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 96)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                
                // MARK: - bottom buttons
                HStack(spacing: 8) {
                    if show_adding_row {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            show_adding_row = false
                        } label: {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .padding(.horizontal).padding(.vertical, pass_row_focus == nil ? 24 : 16)
                        }
                        .font(.title3)
                        .fontWeight(.medium)
                        .fontDesign(app_font_design)
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(Color.accentColor)
                        .tint(Color.accentColor.opacity(0.15))
                    }
                    
                    Button {
                        addNew_action()
                    } label: {
                        HStack {
                            Text(addNew_text)
                                .contentTransition(.numericText(value: Double(addNew_text.hashValue)))
                                .animation(.snappy, value: addNew_text)
                            
                            Image(systemName: addNew_icon)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, pass_row_focus == nil ? 24 : 16)
                    }
                    .font(.title3)
                    .fontWeight(.medium)
                    .fontDesign(app_font_design)
                    .buttonStyle(.glassProminent)
                    .disabled(!addNew_shouldBeActive)
                    .foregroundStyle(addNew_shouldBeActive ? Color.accentColor : Color.primary)
                    .tint(addNew_shouldBeActive ? Color.accentColor.opacity(0.15) : colorScheme == .dark ? Color.black.opacity(0.1) : Color.clear)
                }
                .padding()
            }
            .navigationTitle("Passes")
            .ignoresSafeArea(edges: show_adding_row ? [] : .bottom)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $show_pass_view) {
                if let pass_to_view {
                    PassView(pass: pass_to_view)
                }
            }
        }
    }
    
    // MARK: - functions
    private func delete_pass(at offsets: IndexSet) {
        let items = offsets.map { sorted_passes[$0] }
        for pass in items {
            modelContext.delete(pass)
        }
    }
    
    private func save_pass() {
        let new_pass = Pass(
            id: UUID(),
            name: new_name,
            expiry_date: new_expiry_date,
            is_principal: false,
            image: qr_image_data
        )
        
        modelContext.insert(new_pass)
        
        // reset variables
        new_name = ""
        new_expiry_date = Date()
        picked_image = nil
        qr_image_data = nil
        image_status = .empty
        show_adding_row = false
    }
    
    private func process_image(newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        
        image_status = .empty
        qr_image_data = nil
        
        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    
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
#Preview("Add Pass View - Full") {
    // memory containers
    let schema = Schema([Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // mock data
    let pass1 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        is_principal: false,
        image: UIImage(named: "sample_code")?.pngData()
    )
    let pass2 = Pass(
        id: UUID(),
        name: "Weekly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        is_principal: false,
        image: UIImage(named: "sample_code")?.pngData()
    )
    let pass3 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass4 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass5 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass6 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass7 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass8 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    let pass9 = Pass(
        id: UUID(),
        name: "Monthly Pass",
        expiry_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
        is_principal: false,
        image: nil
    )
    
    container.mainContext.insert(pass1)
    container.mainContext.insert(pass2)
    container.mainContext.insert(pass3)
    container.mainContext.insert(pass4)
    container.mainContext.insert(pass5)
    container.mainContext.insert(pass6)
    container.mainContext.insert(pass7)
    container.mainContext.insert(pass8)
    container.mainContext.insert(pass9)
    
    // view
    return AddPassView()
        .modelContainer(container)
}

#Preview("Add Pass View - Empty") {
    // memory container
    let schema = Schema([Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // view
    return AddPassView()
        .modelContainer(container)
}
