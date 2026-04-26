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
    private var active_passes: [Pass] {
        passes.filter { $0.expiry_date >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.expiry_date < $1.expiry_date }
    }
    private var expired_passes: [Pass] {
        passes.filter { $0.expiry_date < Calendar.current.startOfDay(for: Date()) }.sorted { $0.expiry_date > $1.expiry_date }
    }
    private var principal_pass: Pass? {
        passes.first(where: { $0.is_principal })
    }
    
    // focus variables
    @FocusState private var pass_row_focus: pass_row_focus?
    
    // new pass variables
    @State private var show_adding_row: Bool = false
    @State private var pass_to_edit: Pass? = nil
    @State private var new_name: String = ""
    @State private var new_expiry_date: Date = Date()
    @State private var active_expanded: Bool = true
    @State private var expired_expanded: Bool = false
    
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
        } else if !new_name.isEmpty && qr_image_data != nil {
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
                    
                    pass_to_edit = nil
                    pass_row_focus = .name
                    new_name = "Settimanale"
                    
                    withAnimation(.snappy) {
                        active_expanded = false
                        expired_expanded = false
                        show_adding_row = true
                    }
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
                            Section {
                                if active_expanded {
                                    ForEach(active_passes.filter({ pass in
                                        if let pass_to_edit = pass_to_edit {
                                            return pass.id == pass_to_edit.id
                                        }
                                        return true
                                    })) { pass in
                                        passRow(pass: pass)
                                    }
                                    .onDelete { offsets in
                                        delete_passes(at: offsets, from: active_passes)
                                    }
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Text("Active passes")
                                    
                                    Spacer()
                                    
                                    Text("\(active_passes.count)")
                                        .contentTransition(.numericText(value: Double(active_passes.count)))
                                        .animation(.snappy, value: active_passes.count)
                                    
                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(active_expanded ? 0 : -90))
                                        .animation(.snappy, value: active_expanded)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            active_expanded.toggle()
                                        }
                                }
                            } footer: {
                                if !active_passes.isEmpty {
                                    Text("Swipe to the right to add the QR code to the widget")
                                }
                            }
                            .fontDesign(app_font_design)
                            
                            Section {
                                if expired_expanded {
                                    ForEach(expired_passes.filter({ pass in
                                        if let pass_to_edit = pass_to_edit {
                                            return pass.id == pass_to_edit.id
                                        }
                                        return true
                                    })) { pass in
                                        passRow(pass: pass)
                                    }
                                    .onDelete { offsets in
                                        delete_passes(at: offsets, from: expired_passes)
                                    }
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Text("Expired passes")
                                    
                                    Spacer()
                                    
                                    Text("\(expired_passes.count)")
                                        .contentTransition(.numericText(value: Double(expired_passes.count)))
                                        .animation(.snappy, value: expired_passes.count)
                                    
                                    Image(systemName: "chevron.right")
                                        .rotationEffect(.degrees(expired_expanded ? 90 : 0))
                                        .animation(.snappy, value: expired_expanded)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            expired_expanded.toggle()
                                        }
                                }
                            }
                            .fontDesign(app_font_design)
                        }
                        .listSectionSpacing(32)
                        .scrollIndicators(.hidden)
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 96)
                        }
                    }
                }
                
                // MARK: - bottom buttons
                HStack(spacing: 8) {
                    if show_adding_row {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.snappy) {
                                active_expanded = true
                                expired_expanded = false
                                
                                show_adding_row = false
                                pass_to_edit = nil
                            }
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
                            Image(systemName: addNew_icon)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            
                            Text(addNew_text)
                                .contentTransition(.numericText(value: Double(addNew_text.hashValue)))
                                .animation(.snappy, value: addNew_text)
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
        .interactiveDismissDisabled()
    }
    
    // MARK: - functions
    @ViewBuilder
    private func passRow(pass: Pass) -> some View {
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
            .contentShape(Rectangle())
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(.snappy) {
                    pass_to_edit = pass
                    new_name = pass.name
                    new_expiry_date = pass.expiry_date
                    qr_image_data = pass.image
                    image_status = pass.image != nil ? .saved : .empty
                    active_expanded = false
                    expired_expanded = false
                    show_adding_row = true
                }
                pass_row_focus = .name
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
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if pass.expiry_date >= Calendar.current.startOfDay(for: Date()) {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    withAnimation(.snappy) {
                        if pass.is_principal {
                            pass.is_principal = false
                        } else {
                            for p in passes {
                                p.is_principal = false
                            }
                            pass.is_principal = true
                        }
                        
                        try? modelContext.save()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                } label: {
                    Label(pass.is_principal ? "Remove Principal" : "Set Principal", systemImage: pass.is_principal ? "star.slash.fill" : "star.fill")
                }
                .tint(.orange)
            }
        }
    }
    
    private func delete_passes(at offsets: IndexSet, from list: [Pass]) {
        for index in offsets {
            let pass = list[index]
            modelContext.delete(pass)
        }
    }
    
    private func save_pass() {
        if let pass = pass_to_edit {
            // update
            pass.name = new_name
            pass.expiry_date = new_expiry_date
            pass.image = qr_image_data
            
        } else {
            // new
            let new_pass = Pass(
                id: UUID(),
                name: new_name,
                expiry_date: new_expiry_date,
                is_principal: false,
                image: qr_image_data
            )
            modelContext.insert(new_pass)
        }
        
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            new_name = ""
            new_expiry_date = Date()
            picked_image = nil
            qr_image_data = nil
            image_status = .empty
            active_expanded = true
            expired_expanded = true
            show_adding_row = false
            pass_to_edit = nil
        }
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

