import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit

struct PassView: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var modelContext
    @Query private var passes: [Pass]

    @State private var displayedPasses: [Pass] = []
    @State private var searchText = ""
    @State private var pass_filter: PassFilter = .active
    @State private var pass_form_presentation: PassFormPresentation? = nil

    private enum PassFilter: CaseIterable {
        case all
        case active
        case expired

        struct EmptyState {
            let title: String
            let icon: String
            let description: String
        }

        var label: String {
            switch self {
            case .all:
                return String(localized: "All")
            case .active:
                return String(localized: "Active")
            case .expired:
                return String(localized: "Expired")
            }
        }

        var emptyState: EmptyState {
            switch self {
            case .all:
                EmptyState(
                    title: String(localized: "No passes"),
                    icon: "ticket.fill",
                    description: String(localized: "Add a new pass using the button below.")
                )
            case .active:
                EmptyState(
                    title: String(localized: "No active passes"),
                    icon: "checkmark.circle",
                    description: String(localized: "Change the filter to All or Expired to see other passes.")
                )
            case .expired:
                EmptyState(
                    title: String(localized: "No expired passes"),
                    icon: "clock.badge.exclamationmark",
                    description: String(localized: "Change the filter to All or Active to see other passes.")
                )
            }
        }
    }

    private enum PassFormPresentation: Identifiable {
        case new
        case edit(Pass)

        var id: String {
            switch self {
            case .new:
                return "new"
            case .edit(let pass):
                return pass.id.uuidString
            }
        }

        var passToEdit: Pass? {
            if case .edit(let pass) = self { return pass }
            return nil
        }
    }

    private var filteredPasses: [Pass] {
        displayedPasses.filter { matches($0, searchText: searchText) }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Group {
                if passes.isEmpty {
                    ContentUnavailableView(
                        "No passes added",
                        systemImage: "ticket.fill",
                        description: Text("Add a new pass using the button below.")
                    )
                    .foregroundStyle(.secondary)
                    .fontDesign(app_font_design)
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredPasses.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .fontDesign(app_font_design)
                } else if displayedPasses.isEmpty {
                    ContentUnavailableView(
                        pass_filter.emptyState.title,
                        systemImage: pass_filter.emptyState.icon,
                        description: Text(pass_filter.emptyState.description)
                    )
                    .foregroundStyle(.secondary)
                    .fontDesign(app_font_design)
                } else {
                    List {
                        Section {
                            ForEach(filteredPasses) { pass in
                                passRow(pass: pass)
                            }
                            .onDelete { offsets in
                                delete_passes(at: offsets, from: filteredPasses)
                            }
                        } header: {
                            Text("\(filteredPasses.count) \(filteredPasses.count == 1 ? "pass" : "passes")")
                                .contentTransition(.numericText(value: Double(filteredPasses.count)))
                                .animation(.snappy, value: filteredPasses.count)
                        } footer: {
                            if !filteredPasses.isEmpty {
                                Text("Swipe to the right to add the QR code to the widget")
                            }
                        }
                        .fontDesign(app_font_design)
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Passes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(PassFilter.allCases, id: \.self) { filter in
                            Button {
                                HapticFeedback.select()
                                withAnimation(.snappy) {
                                    pass_filter = filter
                                    refreshDisplayedPasses()
                                }
                            } label: {
                                Label {
                                    Text(filter.label)
                                } icon: {
                                    if pass_filter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: pass_filter == .all ? "line.horizontal.3.decrease" : "line.3.horizontal.decrease.circle.fill")
                                .font(pass_filter == .all ? .headline : .title2)
                                .padding(.leading, pass_filter == .all ? 0 : -2)
                                .foregroundStyle(pass_filter != .all ? .blue : .primary)
                            
                            // show the filter label only if the filter is not set to "all"
                            if pass_filter != .all {
                                Text(pass_filter.label)
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .fontDesign(app_font_design)
                    }
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        HapticFeedback.confirm()
                        pass_form_presentation = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .searchable(text: $searchText, prompt: "Search passes")
            .sheet(item: $pass_form_presentation) { presentation in
                PassFormSheet(passToEdit: presentation.passToEdit) {
                    refreshDisplayedPasses()
                }
            }
        }
        .background(app_background_color.ignoresSafeArea())
        .onAppear { refreshDisplayedPasses() }
        .onChange(of: passes.count) { _, _ in refreshDisplayedPasses() }
        .onChange(of: pass_filter) { _, _ in refreshDisplayedPasses() }
    }

    private func refreshDisplayedPasses() {
        let all = passes.sorted { $0.expiry_date > $1.expiry_date }
        let startOfToday = Calendar.current.startOfDay(for: Date())

        displayedPasses = switch pass_filter {
        case .all:
            all
        case .active:
            all.filter { $0.expiry_date >= startOfToday }
        case .expired:
            all.filter { $0.expiry_date < startOfToday }
        }
    }

    private func matches(_ pass: Pass, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        if pass.name.lowercased().contains(query) {
            return true
        }

        let expiryDate = pass.expiry_date
        let searchableDates = [
            expiryDate.formatted(.dateTime.day().month().year()),
            expiryDate.formatted(date: .abbreviated, time: .omitted),
            expiryDate.formatted(date: .long, time: .omitted),
            expiryDate.formatted(date: .numeric, time: .omitted),
            expiryDate.formatted(.dateTime.year()),
            expiryDate.formatted(.dateTime.month(.wide)),
            expiryDate.formatted(.dateTime.month(.abbreviated)),
            expiryDate.formatted(.dateTime.day()),
        ]

        return searchableDates.contains { $0.lowercased().contains(query) }
    }

    // MARK: - Functions
    @ViewBuilder
    private func passRow(pass: Pass) -> some View {
        let is_active = pass.expiry_date >= Calendar.current.startOfDay(for: Date())
        let time_remaining: String = {
            if !is_active {
                let dateString = pass.expiry_date.formatted(.dateTime.day().month().year())
                return String(localized: "Expired on \(dateString)")
            }

            let totalDays = Calendar.current.dateComponents([.day], from: Date(), to: pass.expiry_date).day ?? 0
            if totalDays == 0 { return String(localized: "Expires today") }
            if totalDays == 1 { return String(localized: "Expires tomorrow") }

            return String(localized: "Expires in \(totalDays) days")
        }()

        let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
        let status_color: Color = pass.is_principal ? amber : (is_active ? .green : .red)
        let status_icon: String = pass.is_principal ? "star.fill" : (is_active ? "checkmark.circle.fill" : "xmark.circle.fill")

        HStack(spacing: 12) {
            Image(systemName: status_icon)
                .font(.largeTitle)
                .foregroundStyle(status_color)
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))

            VStack(alignment: .leading, spacing: 4) {
                Text(pass.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(time_remaining)
                    .font(.subheadline)
                    .foregroundStyle(status_color)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.tap()
            pass_form_presentation = .edit(pass)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if is_active {
                Button {
                    HapticFeedback.impactHeavy()
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
                .tint(Color(red: 1.0, green: 0.75, blue: 0.0))
            }
        }
    }

    private func delete_passes(at offsets: IndexSet, from list: [Pass]) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        refreshDisplayedPasses()
    }
}

// MARK: - Secondary Views

private struct PassFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let passToEdit: Pass?
    let onSave: () -> Void

    @State private var name: String
    @State private var expiry_date: Date
    @State private var picked_image: PhotosPickerItem?
    @State private var qr_image_data: Data?
    @State private var preview_image: UIImage?
    @State private var image_status: image_status = .empty
    @State private var is_processing_image = false
    @State private var is_editing: Bool

    init(passToEdit: Pass?, onSave: @escaping () -> Void) {
        self.passToEdit = passToEdit
        self.onSave = onSave

        _name = State(initialValue: passToEdit?.name ?? String(localized: "Weekly"))
        _expiry_date = State(initialValue: passToEdit?.expiry_date ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _qr_image_data = State(initialValue: passToEdit?.image)
        _image_status = State(initialValue: passToEdit?.image != nil ? .saved : .empty)
        _is_editing = State(initialValue: passToEdit == nil)

        if let data = passToEdit?.image, let image = UIImage(data: data) {
            _preview_image = State(initialValue: image)
        }
    }

    private var is_form_editable: Bool {
        passToEdit == nil || is_editing
    }

    private var can_save: Bool {
        is_form_editable && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && qr_image_data != nil && !is_processing_image
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Pass Information")) {
                    LabeledContent(String(localized: "Name")) {
                        if is_form_editable {
                            TextField(String(localized: "Weekly"), text: $name)
                                .multilineTextAlignment(.trailing)
                                .fontDesign(app_font_design)
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

                    if is_form_editable {
                        DatePicker(String(localized: "Expiration Date"), selection: $expiry_date, displayedComponents: .date)
                            .fontDesign(app_font_design)
                            .onChange(of: expiry_date) { _, new_date in
                                let days = Calendar.current.dateComponents([.day], from: Date(), to: new_date).day ?? 0
                                let new_title: String
                                if days <= 14 {
                                    new_title = String(localized: "Weekly")
                                } else if days <= 60 {
                                    new_title = String(localized: "Monthly")
                                } else {
                                    new_title = String(localized: "Annual")
                                }

                                if name != new_title {
                                    withAnimation(.snappy) {
                                        name = new_title
                                    }
                                }
                            }
                    } else {
                        LabeledContent(String(localized: "Expiration Date")) {
                            Text(expiry_date.formatted(.dateTime.day().month().year()))
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
                    if passToEdit != nil && !is_editing {
                        Button(String(localized: "Edit")) {
                            HapticFeedback.confirm()
                            withAnimation(.snappy) {
                                is_editing = true
                            }
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if passToEdit == nil || is_editing {
                        Button {
                            save_pass()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!can_save)
                    }
                }
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

    private func save_pass() {
        HapticFeedback.impactHeavy()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pass = passToEdit {
            pass.name = trimmedName
            pass.expiry_date = expiry_date
            pass.image = qr_image_data
        } else {
            let new_pass = Pass(
                id: UUID(),
                name: trimmedName,
                expiry_date: expiry_date,
                is_principal: false,
                image: qr_image_data
            )
            modelContext.insert(new_pass)
        }

        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
        onSave()
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

// MARK: - Previews
#Preview("Pass View - Full") {
    let schema = Schema([Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

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
        image: UIImage(named: "sample_code")?.pngData()
    )

    container.mainContext.insert(pass1)
    container.mainContext.insert(pass2)
    container.mainContext.insert(pass3)

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            PassView()
                .modelContainer(container)
        }
}

#Preview("Pass View - Empty") {
    let schema = Schema([Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            PassView()
                .modelContainer(container)
        }
}
