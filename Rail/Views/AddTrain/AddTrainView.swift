import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct AddTrainView: View {
    // MARK: - Types

    enum FocusField: Hashable { case number, departure, arrival }

    // MARK: - Properties

    var focusInitially: Bool = false
    @Environment(\.requestReview) var requestReview
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var addTrainStep: AddTrainStep = .addTrain
    @State private var fetchState: FetchState = .idle

    @FocusState private var focusedField: FocusField?

    @State private var trainsFetched: [UUID: [String: Any]] = [:]
    @State private var trainID_selected: UUID? = nil
    @State private var stopsFetched: [[String: Any]] = []
    @State private var stopsSelected: [[String: Any]] = []

    @State private var searchType: SearchType = .stations
    @State private var trainNumber: String = ""
    @State private var departureStation: String = ""
    @State private var arrivalStation: String = ""
    @State private var departureCode: String = ""
    @State private var arrivalCode: String = ""
    @State private var stationSuggestions: [StationSuggestion] = []
    @State private var stationFetchTask: Task<Void, Never>?
    // true while a suggestion is being applied, so the text onChange doesn't clear the code
    @State private var isSelectingStation = false

    @State private var solutionsFetched: [Solution] = []
    @State private var solutionID_selected: UUID? = nil
    @State private var isSaving = false
    @State private var prefetchTask: Task<Void, Never>?
    @State private var prefetchedSegments: [UUID: [PreparedSolutionSegment]] = [:]
    /// Only one solution shows its legs at a time.
    @State private var expandedSolutionID: UUID?
    @State private var solutionSearchText = ""
    @State private var solutionFilters = SolutionFilters()
    @State private var solutionSort: SolutionSort?
    @State private var dateSelected: Date = Date()
    @State private var showDatePickerPopover = false

    // MARK: - Computed

    private var isFocused: Bool { focusedField != nil }

    private var dateSubtitle: String {
        let cal = Calendar.current
        let dateString = dateSelected.formatted(.dateTime.day().month(.abbreviated))
        let timeString = dateSelected.formatted(.dateTime.hour().minute())

        let dayPart: String
        if cal.isDateInYesterday(dateSelected) {
            dayPart = "Yesterday, \(dateString)"
        } else if cal.isDateInToday(dateSelected) {
            dayPart = "Today, \(dateString)"
        } else if cal.isDateInTomorrow(dateSelected) {
            dayPart = "Tomorrow, \(dateString)"
        } else {
            dayPart = dateString
        }
        return "\(dayPart), \(timeString)"
    }

    private var activeStationQuery: String? {
        guard searchType == .stations,
              let field = focusedField,
              field != .number else { return nil }
        return field == .departure ? departureStation : arrivalStation
    }

    private var showsStationSuggestionBar: Bool {
        guard addTrainStep == .addTrain,
              let query = activeStationQuery,
              query.count >= 2 else { return false }
        return true
    }

    private var nextButtonIcon: String {
        switch addTrainStep {
        case .addTrain:
            if trainID_selected != nil {
                return "checkmark"
            } else {
                return "chevron.right"
            }
        case .chooseTrain:
            // stations: choosing a solution is the final step
            return searchType == .stations ? "checkmark" : "chevron.right"
        case .chooseStops:
            return "chevron.right"
        case .chooseDate:
            return "checkmark"
        }
    }

    private var buttonIsActive: Bool {
        guard !isSaving else { return false }

        switch addTrainStep {
        case .addTrain:
            switch searchType {
            case .number:
                return trainNumber.count >= 2
            case .stations:
                return !departureCode.isEmpty && !arrivalCode.isEmpty
            }

        case .chooseTrain:
            return searchType == .stations ? solutionID_selected != nil : trainID_selected != nil

        case .chooseStops:
            return stopsSelected.count >= 2

        case .chooseDate:
            return true
        }
    }

    private var leadingToolbarIcon: String {
        addTrainStep == .addTrain ? "xmark" : "chevron.left"
    }

    /// Trains found by number, shown with the same rows as the station search.
    /// Each is a single leg, so nothing here expands.
    private var numberedTrainRows: [(id: UUID, solution: Solution)] {
        trainsFetched.compactMap { id, train in
            let stops = train["stops"] as? [[String: Any]] ?? []
            guard let first = stops.first, let last = stops.last else { return nil }
            let segment = SolutionSegment(
                origin: first["name"] as? String ?? "",
                destination: last["name"] as? String ?? "",
                departureTime: first["ref_time"] as? Date ?? .distantPast,
                arrivalTime: last["ref_time"] as? Date ?? .distantPast,
                logo: train["logo"] as? String ?? "",
                number: train["number"] as? String ?? "",
                stationCode: "",
                isBus: false
            )
            return (id, Solution(segments: [segment]))
        }
        .sorted { $0.solution.departureTime < $1.solution.departureTime }
    }

    private var solutionFacets: SolutionFacets { SolutionFacets(solutions: solutionsFetched) }

    private var visibleSolutions: [Solution] {
        SolutionQuery.apply(
            to: solutionsFetched,
            searchText: solutionSearchText,
            filters: solutionFilters,
            facets: solutionFacets,
            sort: solutionSort
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                switch addTrainStep {
                case .addTrain:
                    addTrainView
                    
                case .chooseTrain:
                    chooseTrainView
                    
                case .chooseStops:
                    chooseStopsView
                    
                case .chooseDate:
                    ScrollView {
                        DatePicker("", selection: $dateSelected, in: Date()..., displayedComponents: [.date])
                            .datePickerStyle(GraphicalDatePickerStyle())

                        Color.clear
                            .frame(height: 80)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsStationSuggestionBar,
                   let field = focusedField,
                   field != .number {
                    suggestionsPill(field: field)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsStationSuggestionBar)
            .navigationTitle(addTrainStep.title)
            .navigationBarTitleDisplayMode(.inline)
            // .container only: ignoring the keyboard region too would leave the
            // station suggestion bar stranded behind the keyboard
            .ignoresSafeArea(.container, edges: .bottom)
            .background(appBackgroundColor.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        leadingToolbarAction()
                    } label: {
                        Image(systemName: leadingToolbarIcon)
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nextButtonAction()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: nextButtonIcon)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!buttonIsActive)
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(addTrainStep.title)
                            .font(.headline)
                            .fontDesign(appFontDesign)
                            .contentTransition(.numericText(value: Double(addTrainStep.title.hashValue)))
                            .animation(.snappy, value: addTrainStep.title)
                            
                        if addTrainStep == .chooseTrain && searchType == .stations {
                            Text(dateSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(appFontDesign)
                                .contentTransition(.numericText(value: dateSelected.timeIntervalSince1970))
                                .animation(.snappy, value: dateSelected)
                        }
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard addTrainStep == .chooseTrain && searchType == .stations else { return }
                        HapticFeedback.select()
                        
                        showDatePickerPopover = true
                    }
                    .popover(isPresented: $showDatePickerPopover) {
                        VStack(spacing: 8) {
                            DatePicker("", selection: $dateSelected, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .labelsHidden()

                            DatePicker("Time", selection: $dateSelected, displayedComponents: [.hourAndMinute])
                        }
                        .padding()
                        .presentationDetents([.medium])
                        .onDisappear {
                            Task { await fetchSolutions() }
                        }
                    }
                }
            }
        }
        .onAppear {
            if focusInitially {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = searchType == .number ? .number : .departure
                }
            }
        }
        .onDisappear {
            stationFetchTask?.cancel()
            resetFormState()
        }
        .onChange(of: fetchState) { oldValue, newValue in
            // timer to prevent infinite fetching state
            if oldValue == .idle && newValue == .fetching {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    if fetchState == .fetching {
                        fetchState = .failure
                    }
                }
            }
        }
        .onChange(of: trainNumber) { _, _ in
            guard addTrainStep == .addTrain else { return }
            trainsFetched = [:]
            trainID_selected = nil
            stopsFetched = []
            stopsSelected = []
            fetchState = .idle
        }
        .onChange(of: searchType) { _, newValue in
            stationFetchTask?.cancel()
            stationSuggestions = []
            focusedField = newValue == .number ? .number : .departure
        }
        .onChange(of: focusedField) { oldValue, newValue in
            // tapping straight into the next field still counts as choosing the
            // station the user typed, so the journey stays resolvable
            if let oldValue, oldValue != .number, oldValue != newValue {
                adoptFirstSuggestion(for: oldValue)
            }
            guard let newValue, newValue != .number else {
                stationFetchTask?.cancel()
                stationSuggestions = []
                return
            }
            stationSuggestions = []
            scheduleStationFetch(for: newValue)
        }
        .onChange(of: departureStation) { _, newValue in
            if isSelectingStation { isSelectingStation = false; return }
            departureCode = ""
            guard focusedField == .departure else { return }
            scheduleStationFetch(query: newValue, field: .departure)
        }
        .onChange(of: arrivalStation) { _, newValue in
            if isSelectingStation { isSelectingStation = false; return }
            arrivalCode = ""
            guard focusedField == .arrival else { return }
            scheduleStationFetch(query: newValue, field: .arrival)
        }
        .onChange(of: solutionID_selected) { _, newId in
            prefetchTask?.cancel()
            guard let newId,
                  searchType == .stations,
                  addTrainStep == .chooseTrain,
                  let solution = solutionsFetched.first(where: { $0.id == newId }) else { return }

            prefetchTask = Task {
                let prepared = await SolutionSegmentResolver.resolveAll(solution.trackableSegments)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    prefetchedSegments[newId] = prepared
                }
            }
        }
        .onChange(of: solutionsFetched) { _, _ in
            prefetchTask?.cancel()
            prefetchedSegments = [:]
        }
    }

    // MARK: - Subviews

    var addTrainView: some View {
        Form {
            Section {
                Picker("Search", selection: $searchType) {
                    Text("Stations").tag(SearchType.stations)
                    Text("Train number").tag(SearchType.number)
                }
                .pickerStyle(.segmented)
                // sits close under the toolbar, with the breathing room moved
                // below it so the station fields read as a separate group
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(28)

            if searchType == .stations {
                Section {
                    stationFieldRow(
                        placeholder: NSLocalizedString("Departure", comment: ""),
                        text: firstLetterCapitalized($departureStation),
                        field: .departure,
                        submitLabel: .next
                    ) {
                        if let first = stationSuggestions.first {
                            selectStation(first, field: .departure)
                        } else {
                            adoptFirstSuggestion(for: .departure)
                            focusedField = .arrival
                        }
                    }

                    stationFieldRow(
                        placeholder: NSLocalizedString("Arrival", comment: ""),
                        text: firstLetterCapitalized($arrivalStation),
                        field: .arrival,
                        submitLabel: .search
                    ) {
                        if let first = stationSuggestions.first {
                            selectStation(first, field: .arrival)
                        } else {
                            adoptFirstSuggestion(for: .arrival)
                            focusedField = nil
                        }
                        // both stations resolved: go straight on rather than
                        // making the user reach for the toolbar button
                        if buttonIsActive { nextButtonAction() }
                    }

                    HStack(spacing: 12) {
                        DatePicker("", selection: $dateSelected, displayedComponents: .date)
                            .labelsHidden()
                        DatePicker("", selection: $dateSelected, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                }
            } else {
                Section {
                    TextField("Train number", text: $trainNumber)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .number)
                }
            }
        }
        .formStyle(.grouped)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollIndicators(.hidden)
        .fontDesign(appFontDesign)
    }

    private func stationFieldRow(
        placeholder: String,
        text: Binding<String>,
        field: FocusField,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.words)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit() }

            // only on the field being edited: a clear button on every filled row
            // was just noise once both stations were set
            if focusedField == field, !text.wrappedValue.isEmpty {
                Button {
                    HapticFeedback.tap()
                    text.wrappedValue = ""
                    // stay put so the next station can be typed straight away
                    focusedField = field
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: text.wrappedValue.isEmpty)
        .animation(.snappy, value: focusedField)
    }

    // floating bar shown while typing a station: horizontally scrolling suggestions.
    func suggestionsPill(field: FocusField) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stationSuggestions, id: \.self) { station in
                    Button {
                        selectStation(station, field: field)
                    } label: {
                        Text(station.name)
                            .font(.subheadline).fontWeight(.medium)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(height: 32)
                            .padding(.vertical, 6).padding(.horizontal, 16)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        // fade the chips at the edges, masking before the glass keeps the pill solid
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .glassEffect(.regular)
    }

    @ViewBuilder var chooseTrainView: some View {
        switch fetchState {
        case .idle:
            EmptyView()
            
        case .fetching:
            ContentUnavailableView {
                Label {
                    Text(fetchState.title)
                } icon: {
                    Image(systemName: fetchState.icon)
                        .symbolEffect(.breathe.pulse.wholeSymbol, options: .repeat(.continuous))
                }
            } description: {
                Text(fetchState.description)
            }
            .padding()
            .foregroundColor(fetchState.color)
            
        case .success:
            if searchType == .stations {
                chooseSolutionView
            } else {
                chooseNumberedTrainView
            }

        case .failure:
            ContentUnavailableView(
                fetchState.title,
                systemImage: fetchState.icon,
                description: Text(fetchState.description)
            )
            .padding()
            .foregroundColor(fetchState.color)
        }
    }

    var chooseNumberedTrainView: some View {
        List {
            ForEach(numberedTrainRows, id: \.id) { row in
                let isSelected = trainID_selected == row.id

                SolutionRow(
                    solution: row.solution,
                    isExpanded: false,
                    priceRank: nil,
                    onToggleExpanded: {}
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isSaving else { return }
                    HapticFeedback.select()
                    withAnimation(.snappy) {
                        trainID_selected = isSelected ? nil : row.id
                    }
                }
                .listRowBackground(isSelected ? Color.accentColor.opacity(0.06) : nil)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .scrollIndicators(.hidden)
        .disabled(isSaving)
    }

    var chooseSolutionView: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(visibleSolutions) { solution in
                    let isSelected = solutionID_selected == solution.id
                    // while one solution is open the rest recede, so the legs on
                    // screen clearly belong to the row you opened
                    let isDimmed = expandedSolutionID != nil && expandedSolutionID != solution.id

                    SolutionRow(
                        solution: solution,
                        isExpanded: expandedSolutionID == solution.id,
                        priceRank: priceRank(for: solution),
                        onToggleExpanded: { toggleExpanded(solution) }
                    )
                    .opacity(isDimmed ? 0.4 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isSaving else { return }
                        HapticFeedback.select()
                        withAnimation(.snappy) {
                            solutionID_selected = isSelected ? nil : solution.id
                        }
                    }
                    .listRowBackground(
                        isSelected ? Color.accentColor.opacity(isDimmed ? 0.03 : 0.06) : nil
                    )
                    .id(solution.id)
                }
            }
            .listStyle(.insetGrouped)
            // as scroll padding rather than a trailing row, so the last solution
            // keeps the section's rounded bottom corners
            .contentMargins(.bottom, 80, for: .scrollContent)
            .scrollIndicators(.hidden)
            .disabled(isSaving)
            .overlay {
                if visibleSolutions.isEmpty && !solutionsFetched.isEmpty {
                    if solutionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "No matching solutions",
                            systemImage: "line.3.horizontal.decrease",
                            description: Text("Clear a filter to see more journeys.")
                        )
                        .foregroundStyle(Color.secondary)
                    } else {
                        ContentUnavailableView.search(text: solutionSearchText)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .searchable(text: $solutionSearchText, prompt: "Search solutions")
            .toolbar {
                ToolbarItem(placement: .bottomBar) { solutionSortMenu }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { solutionFilterMenu }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .onAppear { scrollToNextSolution(proxy: proxy, animated: false) }
        }
    }

    private var solutionSortMenu: some View {
        Menu {
            ForEach([SolutionSortField.duration, .price], id: \.self) { field in
                Button {
                    HapticFeedback.select()
                    withAnimation(.snappy) { cycleSort(field) }
                } label: {
                    let isActive = solutionSort?.field == field
                    Label {
                        Text(field == .duration ? "Duration" : "Cost")
                    } icon: {
                        if let sort = solutionSort, sort.field == field {
                            Image(systemName: sort.icon)
                        }
                    }
                    .foregroundStyle(isActive ? Color.blue : Color.primary)
                }
            }

            if solutionSort != nil {
                ControlGroup {
                    Button(role: .destructive) {
                        HapticFeedback.select()
                        withAnimation(.snappy) { solutionSort = nil }
                    } label: {
                        Label("Clear order", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: solutionSort == nil ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle.fill")
                .font(solutionSort == nil ? .headline : .title2)
                .foregroundStyle(solutionSort == nil ? Color.primary : Color.blue)
        }
    }

    @ViewBuilder private var solutionFilterMenu: some View {
        let facets = solutionFacets
        let currency = solutionsFetched.first?.currency ?? "\u{20AC}"

        Menu {
            if facets.changeOptions.count > 1 {
                Menu {
                    ForEach(facets.changeOptions, id: \.self) { option in
                        filterButton(
                            title: changeCountLabel(option),
                            isOn: solutionFilters.changes.contains(option)
                        ) {
                            toggle(&solutionFilters.changes, option)
                        }
                    }
                } label: {
                    Label("Changes", systemImage: "tram.fill")
                        .foregroundStyle(solutionFilters.changes.isEmpty ? Color.primary : Color.blue)
                }
            }

            bucketMenu(
                title: "Duration",
                systemImage: "clock",
                buckets: facets.durationBuckets,
                selection: solutionFilters.durationBuckets,
                label: { $0.durationLabel },
                toggle: { toggle(&solutionFilters.durationBuckets, $0) }
            )

            bucketMenu(
                title: "Cost",
                systemImage: "eurosign",
                buckets: facets.priceBuckets,
                selection: solutionFilters.priceBuckets,
                label: { $0.priceLabel(currency: currency) },
                toggle: { toggle(&solutionFilters.priceBuckets, $0) }
            )

            if solutionFilters.isActive {
                ControlGroup {
                    Button(role: .destructive) {
                        HapticFeedback.select()
                        withAnimation(.snappy) { solutionFilters = SolutionFilters() }
                    } label: {
                        Label("Clear filters", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: solutionFilters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(solutionFilters.isActive ? .title2 : .headline)
                .foregroundStyle(solutionFilters.isActive ? Color.blue : Color.primary)
        }
        .disabled(facets.isEmpty)
    }

    @ViewBuilder private func bucketMenu(
        title: LocalizedStringKey,
        systemImage: String,
        buckets: [SolutionBucket],
        selection: Set<Int>,
        label: @escaping (SolutionBucket) -> String,
        toggle: @escaping (Int) -> Void
    ) -> some View {
        if buckets.count > 1 {
            Menu {
                ForEach(buckets) { bucket in
                    filterButton(title: label(bucket), isOn: selection.contains(bucket.id)) {
                        toggle(bucket.id)
                    }
                }
            } label: {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(selection.isEmpty ? Color.primary : Color.blue)
            }
        }
    }

    private func filterButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.select()
            withAnimation(.snappy) { action() }
        } label: {
            Label {
                Text(title)
            } icon: {
                if isOn { Image(systemName: "checkmark") }
            }
            .foregroundStyle(isOn ? Color.blue : Color.primary)
        }
    }

    var chooseStopsView: some View {
        ZStack(alignment: .bottom) {
            List {
                ForEach(stopsFetched.enumerated(), id: \.offset) { index, stop in
                    let name = stop["name"] as? String ?? ""
                    let ref_time = stop["ref_time"] as? Date ?? .distantPast
                    
                    let is_selected = stopsSelected.contains(where: { $0["name"] as? String == name })
                    
                    Button {
                        stopsSelected = selectStops(stopsFetched: stopsFetched, currentSelection: stopsSelected, tappedIndex: index)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: is_selected ? "checkmark.circle.fill" : "circle")
                                .font(.title)
                                .foregroundStyle(is_selected ? Color.accentColor : Color.primary)
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer(minLength: 16)
                            
                            Text(ref_time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.primary)
                        .padding(4)
                        .contentShape(Rectangle())
                    }
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 120, for: .scrollContent)

            Button {
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.title)
                        .foregroundStyle(Color.yellow.mix(with: .black, by: 0.05))
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 5.0)))
                    
                    Text("Choose only the departure and arrival stations. Intermediate stops are selected automatically.")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
                .fontDesign(appFontDesign)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.yellow.opacity(0.05))
            .foregroundStyle(Color.yellow.mix(with: .black, by: 0.1))
            .padding(.horizontal, 24).padding(.bottom, 24)
            .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Actions

    private func leadingToolbarAction() {
        guard !isSaving else { return }
        HapticFeedback.tap()

        if addTrainStep == .addTrain {
            if isFocused {
                focusedField = nil
            } else {
                dismiss()
            }
        } else {
            backButtonAction()
        }
    }

    private func resetFormState() {
        trainsFetched = [:]
        trainNumber = ""
        departureStation = ""
        arrivalStation = ""
        departureCode = ""
        arrivalCode = ""
        stationSuggestions = []
        stationFetchTask?.cancel()
        prefetchTask?.cancel()
        solutionsFetched = []
        solutionID_selected = nil
        prefetchedSegments = [:]
        isSaving = false
        trainID_selected = nil
        dateSelected = Date()
        addTrainStep = .addTrain
        fetchState = .idle
    }

    private func backButtonAction() -> Void {
        switch addTrainStep {
        case .addTrain:
            /// reset variables
            focusedField = nil

        case .chooseTrain:
            /// update focus
            focusedField = nil
            
            /// change view
            addTrainStep = .addTrain
            
            /// reset variables
            trainsFetched.removeAll()
            trainID_selected = nil
            prefetchTask?.cancel()
            solutionsFetched.removeAll()
            solutionID_selected = nil
            prefetchedSegments = [:]
            isSaving = false

            /// fetching status
            fetchState = .idle
            
        case .chooseStops:
            /// change view
            addTrainStep = .chooseTrain
            
            /// reset variables
            stopsFetched.removeAll()
            stopsSelected.removeAll()
            
        case .chooseDate:
            /// change view
            addTrainStep = .chooseStops
            
            /// reset variables
            dateSelected = Date()
        }
    }
    private func nextButtonAction() -> Void {
        switch addTrainStep {
        case .addTrain:
            if trainID_selected == nil {
                /// haptic feedback
                HapticFeedback.confirm()
                
                /// reset focus
                focusedField = nil

                /// change view
                addTrainStep = .chooseTrain

                /// actions
                if searchType == .number {
                    Task { await fetchTrains() }
                } else {
                    Task { await fetchSolutions() }
                }
            } else {
                /// haptic feedback
                HapticFeedback.impactHeavy()
                
                /// actions
                saveTrain()
                
                /// change view
                dismiss()
            }
            
        case .chooseTrain:
            if searchType == .stations {
                guard !isSaving, solutionID_selected != nil else { return }

                /// haptic feedback
                HapticFeedback.impactHeavy()

                /// stations: a solution is fully specified, save it directly
                isSaving = true
                Task {
                    await saveSolution()
                    dismiss()
                }
            } else {
                /// haptic feedback
                HapticFeedback.confirm()

                /// change view
                addTrainStep = .chooseStops

                /// actions
                saveStops()
            }

        case .chooseStops:
            /// haptic feedback
            HapticFeedback.confirm()
            
            /// change view
            addTrainStep = .chooseDate
            
        case .chooseDate:
            /// haptic feedback
            HapticFeedback.impactHeavy()
            
            /// actions
            saveTrain()
            
            /// change view
            dismiss()
        }
    }

    private func toggle(_ set: inout Set<Int>, _ value: Int) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// ascending → descending → off
    private func cycleSort(_ field: SolutionSortField) {
        guard let current = solutionSort, current.field == field else {
            solutionSort = SolutionSort(field: field, isAscending: true)
            return
        }
        solutionSort = current.isAscending ? SolutionSort(field: field, isAscending: false) : nil
    }

    private func toggleExpanded(_ solution: Solution) {
        guard solution.segments.count > 1 else { return }
        HapticFeedback.select()
        withAnimation(.snappy) {
            // opening one closes whichever was open
            expandedSolutionID = expandedSolutionID == solution.id ? nil : solution.id
        }
    }

    /// Places a fare on the green-to-red ramp against the others on screen.
    private func priceRank(for solution: Solution) -> SolutionPriceRank? {
        guard let price = solution.price else { return nil }
        let prices = visibleSolutions.compactMap(\.price)
        guard let cheapest = prices.min(), let priciest = prices.max(), cheapest < priciest else { return nil }
        return SolutionPriceRank(position: (price - cheapest) / (priciest - cheapest))
    }

    // on open, jump straight to the next departure from now so the user can catch it
    private func scrollToNextSolution(proxy: ScrollViewProxy, animated: Bool = false) {
        let now = Date()
        guard let target = solutionsFetched.first(where: { $0.departureTime >= now }) else { return }

        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
            } else {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func scheduleStationFetch(for field: FocusField) {
        let query = field == .departure ? departureStation : arrivalStation
        scheduleStationFetch(query: query, field: field)
    }

    private func scheduleStationFetch(query: String, field: FocusField) {
        stationFetchTask?.cancel()

        guard query.count >= 2 else {
            stationSuggestions = []
            return
        }

        stationFetchTask = Task(priority: .userInitiated) {
            await fetchStations(for: query, field: field)
        }
    }

    private func fetchStations(for query: String, field: FocusField) async {
        guard query.count >= 2 else {
            await MainActor.run {
                stationSuggestions = []
            }
            return
        }

        guard !Task.isCancelled else { return }
        let results = await TrenitaliaAPI().stationAutocomplete(name: query)

        await MainActor.run {
            guard !Task.isCancelled else { return }
            guard focusedField == field else { return }
            let current = field == .departure ? departureStation : arrivalStation
            guard current == query else { return }
            stationSuggestions = results
        }
    }

    /// Commits the top suggestion for a field the user typed into but never
    /// picked from, so the code needed to fetch solutions is still filled in.
    private func adoptFirstSuggestion(for field: FocusField) {
        guard let match = stationSuggestions.first else { return }

        switch field {
        case .departure:
            guard departureCode.isEmpty,
                  !departureStation.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if departureStation != match.name {
                isSelectingStation = true
                departureStation = match.name
            }
            departureCode = match.code
        case .arrival:
            guard arrivalCode.isEmpty,
                  !arrivalStation.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if arrivalStation != match.name {
                isSelectingStation = true
                arrivalStation = match.name
            }
            arrivalCode = match.code
        case .number:
            break
        }
    }

    private func firstLetterCapitalized(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = $0.isEmpty ? $0 : $0.prefix(1).uppercased() + $0.dropFirst() }
        )
    }

    private func selectStation(_ station: StationSuggestion, field: FocusField) {
        HapticFeedback.select()
        stationSuggestions = []
        isSelectingStation = true
        if field == .departure {
            departureStation = station.name
            departureCode = station.code
            focusedField = .arrival
        } else {
            arrivalStation = station.name
            arrivalCode = station.code
            focusedField = nil
        }
    }

    private func fetchSolutions() async {
        fetchState = .fetching

        let results = await TrenitaliaAPI().trainSolutions(
            departureLocationId: departureCode,
            arrivalLocationId: arrivalCode,
            departureTime: dateSelected
        )

        await MainActor.run {
            solutionsFetched = results
            fetchState = results.isEmpty ? .failure : .success
        }
    }

    // saves the selected solution: each leg becomes its own train, so connected
    // journeys render with the connection manager just like in TodayView.
    private func saveSolution() async {
        guard let solution = solutionsFetched.first(where: { $0.id == solutionID_selected }) else {
            await MainActor.run { isSaving = false }
            return
        }

        // wait for the prefetch started on selection instead of re-resolving from scratch
        if let prefetchTask {
            await prefetchTask.value
        }

        let preparedSegments: [PreparedSolutionSegment]
        if let cached = prefetchedSegments[solution.id], cached.count == solution.segments.count {
            preparedSegments = cached
        } else {
            preparedSegments = await SolutionSegmentResolver.resolveAll(solution.trackableSegments)
        }

        await MainActor.run {
            for prepared in preparedSegments {
                saveSegment(
                    info: prepared.info,
                    fromStation: prepared.fromStation,
                    toStation: prepared.toStation,
                    dayOffset: prepared.dayOffset
                )
            }
            try? modelContext.save()
            reloadWidgetTimelines()
            isSaving = false
        }
    }

    private func saveSegment(info: [String: Any], fromStation: String, toStation: String, dayOffset: Int = 0) {
        let id = UUID()
        
        func offsetDate(_ date: Date) -> Date {
            if dayOffset == 0 { return date }
            return Calendar.current.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }

        let train = Train(
            id: id,
            logo: info["logo"] as? String ?? "",
            number: info["number"] as? String ?? "",
            identifier: info["identifier"] as? String ?? "",
            provider: info["provider"] as? String ?? "",
            last_update_time: offsetDate(info["last_update_time"] as? Date ?? Date()),
            delay: dayOffset != 0 ? 0 : (info["delay"] as? Int ?? 0),
            direction: info["direction"] as? String ?? "",
            issue: info["issue"] as? String ?? ""
        )
        modelContext.insert(train)

        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.map { $0["name"] as? String ?? "" }
        let fromIdx = names.firstIndex(of: fromStation)
        let toIdx = names.firstIndex(of: toStation)

        for (i, stop) in stops.enumerated() {
            // mark only the stops on the ridden segment (origin → destination) as selected
            let is_selected: Bool = {
                guard let f = fromIdx, let t = toIdx else { return false }
                return i >= f && i <= t
            }()

            let stopToAdd = Stop(
                id: id,
                name: stop["name"] as? String ?? "",
                platform: stop["platform"] as? String ?? "",
                weather: stop["weather"] as? String ?? "",
                is_selected: is_selected,
                status: dayOffset != 0 ? 0 : (stop["status"] as? Int ?? 0),
                is_completed: dayOffset != 0 ? false : (stop["is_completed"] as? Bool ?? false),
                is_in_station: dayOffset != 0 ? false : (stop["is_in_station"] as? Bool ?? false),
                dep_delay: dayOffset != 0 ? 0 : (stop["dep_delay"] as? Int ?? 0),
                arr_delay: dayOffset != 0 ? 0 : (stop["arr_delay"] as? Int ?? 0),
                dep_time_id: offsetDate(stop["dep_time_id"] as? Date ?? .distantPast),
                arr_time_id: offsetDate(stop["arr_time_id"] as? Date ?? .distantPast),
                dep_time_eff: dayOffset != 0 ? offsetDate(stop["dep_time_id"] as? Date ?? .distantPast) : offsetDate(stop["dep_time_eff"] as? Date ?? .distantPast),
                arr_time_eff: dayOffset != 0 ? offsetDate(stop["arr_time_id"] as? Date ?? .distantPast) : offsetDate(stop["arr_time_eff"] as? Date ?? .distantPast),
                ref_time: offsetDate(stop["ref_time"] as? Date ?? .distantPast)
            )
            modelContext.insert(stopToAdd)
        }
    }

    private func fetchTrains() async {
        fetchState = .fetching
        
        Task {
            /// fetch from both providers
            let results = await fetchCommonTrainList(number : trainNumber)
            
            /// assign results to variables
            for result in results {
                trainsFetched[UUID()] = result
            }
            
            /// define fetching status again
            await MainActor.run {
                if trainsFetched.isEmpty {
                    fetchState = .failure
                } else {
                    fetchState = .success
                }
            }
        }
    }

    private func saveStops() {
        let train = trainsFetched.filter { $0.key == trainID_selected }.first
        let stops = train?.value["stops"] as? [[String: Any]] ?? []
        for stop in stops {
            stopsFetched.append(stop)
        }
    }

    private func selectStops(stopsFetched: [[String: Any]], currentSelection: [[String: Any]], tappedIndex: Int) -> [[String: Any]] {
        let selectedIndices: [Int] = currentSelection.compactMap { selected in
            guard let name = selected["name"] as? String else { return nil }
            return stopsFetched.firstIndex(where: {
                ($0["name"] as? String) == name
            })
        }.sorted()

        let lowerBound = selectedIndices.first
        let upperBound = selectedIndices.last

        let isSelected = selectedIndices.contains(tappedIndex)

        if isSelected {
            /// Shrink range
            guard let lower = lowerBound else { return [] }

            let newUpper = tappedIndex - 1
            if newUpper >= lower {
                return Array(stopsFetched[lower...newUpper])
            } else {
                return []
            }
        } else {
            /// Extend range
            if let lower = lowerBound, let upper = upperBound {
                let newLower = Swift.min(lower, tappedIndex)
                let newUpper = Swift.max(upper, tappedIndex)
                return Array(stopsFetched[newLower...newUpper])
            } else {
                return [stopsFetched[tappedIndex]]
            }
        }
    }

    private func saveTrain() {
        // unique id for train and stops
        let id = UUID()
        
        // MARK: - day difference for future dates
        /// get the first stop selected reference time
        let firstStop_refTime = stopsFetched.first?["ref_time"] as? Date ?? .distantPast
        
        /// compare its day with the selected date
        let startOfDay_dateSelected = Calendar.current.startOfDay(for: dateSelected)
        let startOfDay_firstStop_refTime = Calendar.current.startOfDay(for: firstStop_refTime)
        
        /// calculate the day difference
        let dayDifference = abs(Calendar.current.dateComponents([.day], from: startOfDay_dateSelected, to: startOfDay_firstStop_refTime).day ?? 0)
        
        // MARK: - add train
        /// get selected train
        let trainSelected = trainsFetched.filter { $0.key == trainID_selected }.first
        
        /// get details
        let logo = trainSelected?.value["logo"] as? String ?? ""
        let number = trainSelected?.value["number"] as? String ?? ""
        let identifier = trainSelected?.value["identifier"] as? String ?? ""
        let provider = trainSelected?.value["provider"] as? String ?? ""
        
        let last_update_time = trainSelected?.value["last_update_time"] as? Date ?? Date()
        let delay = trainSelected?.value["delay"] as? Int ?? 0
        let direction = trainSelected?.value["direction"] as? String ?? ""
        
        let issue = trainSelected?.value["issue"] as? String ?? ""

        /// adjust identifier timestamp based on day difference
        let identifierString: String = {
            guard provider != "italo" else { return trainNumber }
            
            let components = identifier.split(separator: "/").map { String($0) }
            var timestamp = Int(components.last ?? "") ?? 0
            let adjustedDate = Date(timeIntervalSince1970: TimeInterval(timestamp)).addingTimeInterval(TimeInterval(dayDifference) * 86_400)
            timestamp = Int(adjustedDate.timeIntervalSince1970)
            return components.dropLast().joined(separator: "/") + "/\(timestamp)"
        }()
        
        /// save to database
        let trainToAdd = Train(
            id: id,
            logo: logo,
            number: number,
            identifier: identifierString,
            provider: provider,
            last_update_time: last_update_time,
            delay: delay,
            direction: direction,
            issue: issue
        )
        modelContext.insert(trainToAdd)
        
        var addedStops: [Stop] = []

        // MARK: - add stops
        for stop in stopsFetched {
            /// fetch details
            let name = stop["name"] as? String ?? ""
            let platform = stop["platform"] as? String ?? ""
            let weather = stop["weather"] as? String ?? ""
            
            let is_selected = stopsSelected.contains(where: { $0["name"] as? String == name })
            let status = stop["status"] as? Int ?? 0
            let is_completed = stop["is_completed"] as? Bool ?? false
            let is_in_station = stop["is_in_station"] as? Bool ?? false
            
            let dep_delay = stop["dep_delay"] as? Int ?? 0
            let arr_delay = stop["arr_delay"] as? Int ?? 0
            
            var dep_time_id = stop["dep_time_id"] as? Date ?? .distantPast
            var dep_time_eff = stop["dep_time_eff"] as? Date ?? .distantPast
            var arr_time_id = stop["arr_time_id"] as? Date ?? .distantPast
            var arr_time_eff = stop["arr_time_eff"] as? Date ?? .distantPast
            var ref_time = stop["ref_time"] as? Date ?? .distantPast
            
            /// adjust timestamps based on day difference
            dep_time_id.addTimeInterval(TimeInterval(dayDifference) * 86_400)
            dep_time_eff.addTimeInterval(TimeInterval(dayDifference) * 86_400)
            arr_time_id.addTimeInterval(TimeInterval(dayDifference) * 86_400)
            arr_time_eff.addTimeInterval(TimeInterval(dayDifference) * 86_400)
            ref_time.addTimeInterval(TimeInterval(dayDifference) * 86_400)
            
            /// save to database
            let stopToAdd = Stop(
                id: id,
                name: name,
                platform: platform,
                weather: weather,
                is_selected: is_selected,
                status: status,
                is_completed: is_completed,
                is_in_station: is_in_station,
                dep_delay: dep_delay,
                arr_delay: arr_delay,
                dep_time_id: dep_time_id,
                arr_time_id: arr_time_id,
                dep_time_eff: dep_time_eff,
                arr_time_eff: arr_time_eff,
                ref_time: ref_time
            )
            modelContext.insert(stopToAdd)
            addedStops.append(stopToAdd)
        }
        
        try? modelContext.save()
        
        // MARK: - calendar sync
        if let profile = profiles.primary, profile.calendarSettings.autoSyncToCalendar {
            let settings = profile.calendarSettings
            Task {
                await CalendarManager.shared.syncTrainEvent(
                    train: trainToAdd,
                    stops: addedStops,
                    seats: [],
                    titleFormat: settings.titleFormat,
                    calendarIdentifier: settings.calendarIdentifier,
                    travelTime: settings.travelTime
                )
            }
        }
        
        reloadWidgetTimelines()
    }
}

extension AddTrainView {
    init(
        previewView: AddTrainStep,
        stopsFetched: [[String: Any]] = [],
        stopsSelected: [[String: Any]] = [],
        departureStation: String = "",
        focusInitially: Bool = false
    ) {
        self.focusInitially = focusInitially
        self._addTrainStep = State(initialValue: previewView)
        self._stopsFetched = State(initialValue: stopsFetched)
        self._stopsSelected = State(initialValue: stopsSelected)
        self._departureStation = State(initialValue: departureStation)
    }

    // preview helper for the "Choose Train" step (number search → trains, stations search → solutions)
    init(
        previewView: AddTrainStep,
        searchType: SearchType,
        fetching: FetchState,
        trainsFetched: [UUID: [String: Any]] = [:],
        solutionsFetched: [Solution] = [],
        expandedSolutionID: UUID? = nil,
        selectedSolutionID: UUID? = nil
    ) {
        self._addTrainStep = State(initialValue: previewView)
        self._searchType = State(initialValue: searchType)
        self._fetchState = State(initialValue: fetching)
        self._trainsFetched = State(initialValue: trainsFetched)
        self._solutionsFetched = State(initialValue: solutionsFetched)
        self._expandedSolutionID = State(initialValue: expandedSolutionID)
        self._solutionID_selected = State(initialValue: selectedSolutionID)
    }
}

#Preview("Add Train View") {
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(previewView: .addTrain)
                .modelContainer(container)
        }
}

#Preview("Choose Stops View") {
    let schema = Schema([Train.self, Stop.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    
    let start = Date()
    let mockStops: [[String: Any]] = [
        ["name": "Torino Porta Nuova", "ref_time": start],
        ["name": "Torino Porta Susa", "ref_time": start.addingTimeInterval(600)],      // +10 min
        ["name": "Milano Centrale", "ref_time": start.addingTimeInterval(3600)],        // +1 hour
        ["name": "Reggio Emilia AV", "ref_time": start.addingTimeInterval(5400)],       // +1.5 hours
        ["name": "Bologna Centrale", "ref_time": start.addingTimeInterval(7200)],       // +2 hours
        ["name": "Firenze S.M.N.", "ref_time": start.addingTimeInterval(10800)],       // +3 hours
        ["name": "Roma Tiburtina", "ref_time": start.addingTimeInterval(16200)],        // +4.5 hours
        ["name": "Roma Termini", "ref_time": start.addingTimeInterval(17100)],          // +4h 45m
        ["name": "Napoli Afragola", "ref_time": start.addingTimeInterval(20700)],       // +5h 45m
        ["name": "Napoli Centrale", "ref_time": start.addingTimeInterval(21600)],       // +6 hours
        ["name": "Salerno", "ref_time": start.addingTimeInterval(23400)]                // +6.5 hours
    ]
    
    do {
        let container = try ModelContainer(for: schema, configurations: modelConfiguration)
        
        return Color(uiColor: .systemBackground)
            .sheet(isPresented: .constant(true)) {
                AddTrainView(
                    previewView: .chooseStops,
                    stopsFetched: mockStops,
                    stopsSelected: [mockStops[0], mockStops[1]]
                )
                .modelContainer(container)
            }
        
    } catch {
        return ContentUnavailableView("SwiftData Error", systemImage: "xmark.octagon", description: Text(error.localizedDescription))
            .foregroundStyle(Color.red)
    }
}

#Preview("Choose Train - number search") {
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self, Favorite.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!

    // mock trains for number "757"
    let trainsFetched: [UUID: [String: Any]] = [
        UUID(): [
            "number": "757",
            "logo": "FR",
            "stops": [
                ["name": "Milano Centrale", "ref_time": start],
                ["name": "Roma Termini", "ref_time": start.addingTimeInterval(3 * 3600)]
            ]
        ],
        UUID(): [
            "number": "757",
            "logo": "IC",
            "stops": [
                ["name": "Torino Porta Nuova", "ref_time": start.addingTimeInterval(1800)],
                ["name": "Napoli Centrale", "ref_time": start.addingTimeInterval(6 * 3600)]
            ]
        ]
    ]

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(
                previewView: .chooseTrain,
                searchType: .number,
                fetching: .success,
                trainsFetched: trainsFetched
            )
            .modelContainer(container)
        }
}

#Preview("Choose Train - stations search") {
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self, Favorite.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    let start = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!

    // mock solutions for Milano Centrale → Roma Termini
    let solutionsFetched: [Solution] = [
        // direct
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Roma Termini",
                departureTime: start, arrivalTime: start.addingTimeInterval(3 * 3600),
                logo: "FR", number: "9612", stationCode: "S01700", isBus: false
            )
        ], price: 51.45),
        // with a connection in Bologna
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Bologna Centrale",
                departureTime: start.addingTimeInterval(900), arrivalTime: start.addingTimeInterval(900 + 64 * 60),
                logo: "FR", number: "9613", stationCode: "S01700", isBus: false
            ),
            SolutionSegment(
                origin: "Bologna Centrale", destination: "Roma Termini",
                departureTime: start.addingTimeInterval(900 + 90 * 60), arrivalTime: start.addingTimeInterval(900 + 90 * 60 + 125 * 60),
                logo: "IC", number: "605", stationCode: "S05043", isBus: false
            )
        ], price: 33.00),
        // train + replacement bus
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Firenze S.M.N.",
                departureTime: start.addingTimeInterval(1800), arrivalTime: start.addingTimeInterval(1800 + 110 * 60),
                logo: "FR", number: "9615", stationCode: "S01700", isBus: false
            ),
            SolutionSegment(
                origin: "Firenze S.M.N.", destination: "Roma Termini",
                departureTime: start.addingTimeInterval(1800 + 140 * 60), arrivalTime: start.addingTimeInterval(1800 + 140 * 60 + 95 * 60),
                logo: "BU", number: "FI451", stationCode: "S06421", isBus: true
            )
        ], price: 21.45)
    ]

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(
                previewView: .chooseTrain,
                searchType: .stations,
                fetching: .success,
                solutionsFetched: solutionsFetched
            )
            .modelContainer(container)
        }
}
