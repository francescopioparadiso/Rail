import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct AddTrainView: View {
    // MARK: - Types

    enum FocusField: Hashable { case number, station(UUID) }

    // MARK: - Properties

    var focusInitially: Bool = false
    @Environment(\.requestReview) var requestReview
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var addTrainStep: AddTrainStep = .addTrain
    /// Which way the steps are sliding, like the Choose Train pages.
    @State private var stepMovesForward = true
    /// Set when a step change shows or leaves a searching or empty placeholder,
    /// which fades rather than slides.
    @State private var stepFades = false
    /// A step change waiting for the update that sets its direction to land.
    @State private var stepRequest: StepRequest?
    @State private var stepRequestChanges: () -> Void = {}
    /// Whether the trains picked so far, pinned over a page, are broken out.
    @State private var pickedSoFarExpanded = false
    @State private var fetchState: FetchState = .idle

    @FocusState private var focusedField: FocusField?

    @State private var trainsFetched: [UUID: [String: Any]] = [:]
    @State private var trainID_selected: UUID? = nil
    @State private var stopsFetched: [[String: Any]] = []
    @State private var stopsSelected: [[String: Any]] = []

    @State private var searchType: SearchType = .stations
    @State private var trainNumber: String = ""
    /// The outbound trip's stations in order, then the return's once added.
    @State private var trips: [[StationEntry]] = [[StationEntry(), StationEntry()]]
    @State private var returnDate: Date = Date()
    /// The station row being dragged by its handle to a new place.
    @State private var stationDrag: StationDrag?
    @ScaledMetric private var stationRowHeight: CGFloat = 52
    @State private var stationSuggestions: [StationSuggestion] = []
    @State private var stationFetchTask: Task<Void, Never>?
    /// The stations around the user, offered on an empty departure field.
    @State private var nearbyStations: [StationSuggestion] = []
    @State private var nearbyStationsTask: Task<Void, Never>?

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
    // searches with stops or a return: one page of trains for each leg
    @State private var searchedLegs: [JourneyLeg] = []
    @State private var legsFetched: [[Solution]] = []
    /// The train picked on each page so far. Going back leaves them in place,
    /// so the pages after keep their trains while they slide away.
    @State private var legChoices: [Solution] = []
    @State private var legPage = 0
    /// Search, filters, sort and open row of the pages not on screen.
    @State private var pageStates: [Int: SolutionListState] = [:]
    /// Every train picked; what gets shown on its own and saved.
    @State private var combinedSolution: Solution?
    /// The picked trains again, joined up day by day for the recap.
    @State private var journeyDays: [Solution] = []
    /// Days open independently in the recap, unlike the one-at-a-time lists.
    @State private var expandedDayIDs: Set<UUID> = []
    @State private var dateSelected: Date = Date()
    @State private var showDatePickerPopover = false

    // MARK: - Computed

    private var isFocused: Bool { focusedField != nil }

    private var dateSubtitle: Text {
        let cal = Calendar.current
        let dateString = dateSelected.formatted(.dateTime.day().month(.abbreviated))
        let timeString = dateSelected.formatted(.dateTime.hour().minute())

        if cal.isDateInYesterday(dateSelected) {
            return Text("Yesterday, \(dateString), \(timeString)")
        }
        if cal.isDateInToday(dateSelected) {
            return Text("Today, \(dateString), \(timeString)")
        }
        if cal.isDateInTomorrow(dateSelected) {
            return Text("Tomorrow, \(dateString), \(timeString)")
        }
        return Text(verbatim: "\(dateString), \(timeString)")
    }

    private var activeStationQuery: String? {
        guard searchType == .stations,
              let field = focusedField,
              field != .number else { return nil }
        return stationText(for: field)
    }

    /// Whether the field being edited is the empty departure, which is offered the
    /// stations nearby instead of matches.
    private var showsNearbyStations: Bool {
        guard let query = activeStationQuery, focusedField == firstStationField else { return false }
        return query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var showsStationSuggestionBar: Bool {
        guard addTrainStep == .addTrain,
              let query = activeStationQuery else { return false }
        return query.count >= 2 || (showsNearbyStations && !nearbyStations.isEmpty)
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
                // a station typed but never resolved can't be searched; an empty one is just ignored
                return trips.allSatisfy { stations in
                    stations.allSatisfy { $0.name.isEmpty || !$0.code.isEmpty }
                        && stations.filter { !$0.code.isEmpty }.count >= 2
                }
            }

        case .chooseTrain:
            guard searchType == .stations else { return trainID_selected != nil }
            // with stops or a return, only once every train is picked
            return isMultiLeg ? combinedSolution != nil : solutionID_selected != nil

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

    private var includesReturn: Bool { trips.count > 1 }

    /// Every trip's stations a pair at a time, each on its trip's own day.
    private var journeyLegs: [JourneyLeg] {
        trips.enumerated().flatMap { trip, entries in
            let stations = entries.filter { !$0.code.isEmpty }
            let date = trip == 0 ? dateSelected : returnDate
            return zip(stations, stations.dropFirst()).map { from, to in
                JourneyLeg(origin: from.name, destination: to.name, originCode: from.code, destinationCode: to.code, date: date)
            }
        }
    }

    private var isMultiLeg: Bool {
        searchType == .stations && journeyLegs.count > 1
    }

    /// The journey the checkmark saves.
    private var selectedSolution: Solution? {
        if isMultiLeg { return combinedSolution }
        return solutionsFetched.first(where: { $0.id == solutionID_selected })
    }

    /// The list the search, sort and filters work on: the one page on screen.
    private var activeSolutions: [Solution] {
        guard isMultiLeg else { return solutionsFetched }
        return combinedSolution == nil ? solutions(onPage: legPage) : []
    }

    private var solutionFacets: SolutionFacets { SolutionFacets(solutions: activeSolutions) }

    private var visibleSolutions: [Solution] {
        SolutionQuery.apply(
            to: activeSolutions,
            searchText: solutionSearchText,
            filters: solutionFilters,
            facets: solutionFacets,
            sort: solutionSort
        )
    }

    /// A page's trains: the first as found, every later one only those leaving
    /// once the train picked before it has arrived.
    private func solutions(onPage page: Int) -> [Solution] {
        guard legsFetched.indices.contains(page) else { return [] }
        guard page > 0 else { return legsFetched[0] }
        guard legChoices.indices.contains(page - 1) else { return [] }
        let arrival = legChoices[page - 1].arrivalTime
        return legsFetched[page].filter { $0.departureTime > arrival }
    }

    private var liveListState: SolutionListState {
        SolutionListState(
            searchText: solutionSearchText,
            filters: solutionFilters,
            sort: solutionSort,
            expandedID: expandedSolutionID
        )
    }

    private func listState(onPage page: Int) -> SolutionListState {
        // under the finished journey the last page keeps how it was left
        if page == legPage && combinedSolution == nil { return liveListState }
        return pageStates[page] ?? SolutionListState()
    }

    private func visibleSolutions(onPage page: Int) -> [Solution] {
        let solutions = solutions(onPage: page)
        let state = listState(onPage: page)
        return SolutionQuery.apply(
            to: solutions,
            searchText: state.searchText,
            filters: state.filters,
            facets: SolutionFacets(solutions: solutions),
            sort: state.sort
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
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
                // every step slides in like the Choose Train pages
                .transition(stepTransition)
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
                    principalTitle
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
                    focusedField = searchType == .number ? .number : firstStationField
                }
            }
        }
        .onDisappear {
            stationFetchTask?.cancel()
            nearbyStationsTask?.cancel()
            nearbyStationsTask = nil
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
            focusedField = newValue == .number ? .number : firstStationField
        }
        .onChange(of: focusedField) { oldValue, newValue in
            // tapping straight into the next field still counts as choosing the
            // station the user typed, so the journey stays resolvable
            if let oldValue, oldValue != .number, oldValue != newValue {
                adoptFirstSuggestion(for: oldValue)
                removeIfEmptyStop(oldValue)
            }
            guard let newValue, newValue != .number else {
                stationFetchTask?.cancel()
                stationSuggestions = []
                return
            }
            stationSuggestions = []
            scheduleStationFetch(for: newValue)
            if newValue == firstStationField { loadNearbyStations() }
        }
        .onChange(of: solutionID_selected) { _, newId in
            prefetchTask?.cancel()
            guard let newId,
                  searchType == .stations,
                  addTrainStep == .chooseTrain,
                  let solution = selectedSolution, solution.id == newId else { return }

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
        // runs after the update that gave the steps their new direction, so the
        // step leaving slides out the way the one arriving slides in
        // the return moves with the outbound, keeping the time between them,
        // so it's never left on a day before it
        .onChange(of: dateSelected) { old, new in
            guard includesReturn else { return }
            returnDate = max(returnDate.addingTimeInterval(new.timeIntervalSince(old)), new)
        }
        .onChange(of: stepRequest) { _, request in
            guard let request else { return }
            withAnimation(stepFades ? .smooth : .snappy) {
                addTrainStep = request.step
                stepRequestChanges()
            }
            stepRequestChanges = {}
        }
    }

    // MARK: - Subviews

    /// Forward pushes the next step in from the trailing edge, back brings the
    /// previous one in from the leading edge.
    private var stepTransition: AnyTransition {
        if stepFades { return .opacity }
        return .asymmetric(
            insertion: .move(edge: stepMovesForward ? .trailing : .leading),
            removal: .move(edge: stepMovesForward ? .leading : .trailing)
        )
    }

    private var principalTitle: some View {
        VStack(spacing: 0) {
            Text(addTrainStep.title)
                .font(.headline)
                .fontDesign(appFontDesign)
                .contentTransition(.numericText(value: Double(addTrainStep.hashValue)))
                .animation(.snappy, value: addTrainStep)

            if addTrainStep == .chooseTrain && searchType == .stations {
                dateSubtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(appFontDesign)
                    .contentTransition(.numericText(value: dateSelected.timeIntervalSince1970))
                    .animation(.snappy, value: dateSelected)
            }
        }
    }

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
                ForEach(trips.indices, id: \.self) { trip in
                    Section {
                        stationsEditor(trip: trip)
                            .listRowInsets(EdgeInsets())
                            // drawn by the editor instead, so it matches the lines
                            // between the stations
                            .listRowSeparator(.hidden, edges: .bottom)

                        HStack(spacing: 12) {
                            DatePicker("", selection: trip == 0 ? $dateSelected : $returnDate, in: returnRange(trip), displayedComponents: .date)
                                .labelsHidden()
                            DatePicker("", selection: trip == 0 ? $dateSelected : $returnDate, in: returnRange(trip), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        // picking a date or time is done with the stations, so
                        // the keyboard goes rather than covering the picker
                        .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                        .frame(minHeight: stationRowHeight)
                        .listRowSeparator(.hidden, edges: .top)
                        .listRowInsets(EdgeInsets(top: 0, leading: Self.stationGutter, bottom: 0, trailing: 16))
                    } header: {
                        if includesReturn {
                            Text(trip == 0 ? "Outbound" : "Return")
                        }
                    }
                }

                Section {
                    returnButton
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
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

    /// Room on the leading side of the station fields, where the buttons that
    /// add a stop sit on the lines between them.
    private static let stationGutter: CGFloat = 44

    /// A trip's stations as one block, so its rows can be dragged around by their
    /// handles, with a button in the gutter to add or remove its stop.
    private func stationsEditor(trip: Int) -> some View {
        let stations = trips[trip]

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    stationRow(station, index: index, trip: trip)
                }
            }

            // the lines stay put while the rows move over them
            ForEach(1..<max(stations.count, 1), id: \.self) { index in
                separatorLine
                    .padding(.leading, Self.stationGutter)
                    .offset(y: CGFloat(index) * stationRowHeight)
            }

            // One button for the trip's one stop: a plus on the line between
            // departure and arrival, and once there's a stop a cross in its row
            // to take it out. Two views, so one fades out as the other fades in.
            if stations.count > 2 {
                stopButton(trip: trip, isStop: true)
                    .offset(y: 1.5 * stationRowHeight - Self.stopButtonSize / 2)
                    .transition(.opacity)
            } else {
                stopButton(trip: trip, isStop: false)
                    .offset(y: stationRowHeight - Self.stopButtonSize / 2)
                    .transition(.opacity)
            }
        }
        // the line down to the date, drawn the same as the ones between stations
        .overlay(alignment: .bottom) {
            separatorLine.padding(.leading, Self.stationGutter)
        }
        .coordinateSpace(.named(StationDrag.space(trip)))
    }

    private static let stopButtonSize: CGFloat = 32

    private func stopButton(trip: Int, isStop: Bool) -> some View {
        Button {
            if isStop {
                removeStop(trip: trip, at: 1)
            } else {
                addStop(trip: trip, at: 1)
            }
        } label: {
            Image(systemName: isStop ? "xmark.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(isStop ? Color.red : Color.blue)
                .frame(width: Self.stationGutter, height: Self.stopButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStop ? "Remove Stop" : "Add Stop")
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 1 / displayScale)
    }

    @Environment(\.displayScale) private var displayScale

    private func stationRow(_ station: StationEntry, index: Int, trip: Int) -> some View {
        let count = trips[trip].count
        let field = FocusField.station(station.id)
        let text = firstLetterCapitalized(stationBinding(station.id))
        let isDragged = stationDrag?.id == station.id
        let placeholder: LocalizedStringKey = index == 0 ? "Departure" : index == count - 1 ? "Arrival" : "Stop"

        return HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.words)
                // station names aren't words to correct or predict; our own
                // suggestions bar does that job
                .autocorrectionDisabled()
                .submitLabel(index == count - 1 && trip == trips.count - 1 ? .search : .next)
                .onSubmit { submitStation(station.id) }

            // only on the field being edited: a clear button on every filled row
            // was just noise once both stations were set
            if focusedField == field, !station.name.isEmpty {
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

            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: stationRowHeight)
                .contentShape(Rectangle())
                .highPriorityGesture(reorderGesture(for: station.id, trip: trip))
                .accessibilityLabel("Reorder")
        }
        .padding(.leading, Self.stationGutter)
        .padding(.trailing, 4)
        .frame(height: stationRowHeight)
        .background {
            if isDragged {
                Color(.secondarySystemGroupedBackground)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
        }
        .offset(y: isDragged ? stationDrag?.offset(at: index, rowHeight: stationRowHeight) ?? 0 : 0)
        .zIndex(isDragged ? 1 : 0)
        // the row under the finger follows it exactly; only the others animate
        .transaction { if isDragged { $0.animation = nil } }
        .animation(.snappy, value: station.name.isEmpty)
        .animation(.snappy, value: focusedField)
    }

    /// Dragging a row by its handle swaps it past the rows it crosses.
    private func reorderGesture(for id: UUID, trip: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(StationDrag.space(trip)))
            .onChanged { value in
                guard let from = trips[trip].firstIndex(where: { $0.id == id }) else { return }
                if stationDrag?.id != id {
                    stationDrag = StationDrag(id: id, startIndex: from, translation: 0)
                    HapticFeedback.select()
                }
                stationDrag?.translation = value.translation.height

                let steps = Int((value.translation.height / stationRowHeight).rounded())
                let target = min(max((stationDrag?.startIndex ?? from) + steps, 0), trips[trip].count - 1)
                guard target != from else { return }
                HapticFeedback.select()
                withAnimation(.snappy) {
                    trips[trip].move(fromOffsets: [from], toOffset: target > from ? target + 1 : target)
                }
            }
            .onEnded { _ in
                withAnimation(.snappy) { stationDrag = nil }
            }
    }

    @ViewBuilder private var returnButton: some View {
        if includesReturn {
            Button(role: .destructive) {
                HapticFeedback.tap()
                if case .station(let id) = focusedField, trips[1].contains(where: { $0.id == id }) {
                    focusedField = nil
                }
                withAnimation(.snappy) { trips.removeLast() }
            } label: {
                returnLabel("Remove Return", systemImage: "minus")
            }
            // the same tinted glass as the Choose Stops tip
            .buttonStyle(.glassProminent)
            .tint(Color.red.opacity(0.15))
            .foregroundStyle(Color.red)
        } else {
            Button(action: addReturn) {
                returnLabel("Add Return", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .tint(Color.blue.opacity(0.15))
            .foregroundStyle(Color.blue)
        }
    }

    // a Label spaces its icon too far from the title for a button this small
    private func returnLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
    }

    // floating bar shown while typing a station: horizontally scrolling suggestions.
    func suggestionsPill(field: FocusField) -> some View {
        StationSuggestionsBar(
            suggestions: showsNearbyStations ? nearbyStations : stationSuggestions,
            isNearby: showsNearbyStations
        ) { station in
            selectStation(station, field: field)
        }
    }

    /// Searching, the results and nothing found fade into one another.
    var chooseTrainView: some View {
        ZStack {
            fetchStateContent
                .transition(.opacity)
        }
        .animation(.smooth, value: fetchState)
    }

    @ViewBuilder private var fetchStateContent: some View {
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
            if isMultiLeg {
                chooseLegsView
            } else if searchType == .stations {
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
        withSolutionTools(ScrollViewReader { proxy in
            solutionList(
                showsNoMatches: visibleSolutions.isEmpty && !activeSolutions.isEmpty,
                searchText: solutionSearchText
            ) {
                ForEach(visibleSolutions) { solution in
                    let isSelected = solutionID_selected == solution.id
                    solutionRow(
                        solution,
                        isSelected: isSelected,
                        expandedID: expandedSolutionID,
                        rankedAmong: visibleSolutions
                    ) {
                        withAnimation(.snappy) {
                            solutionID_selected = isSelected ? nil : solution.id
                        }
                    }
                }
            }
            .onAppear { scrollToNextSolution(in: solutionsFetched, after: dateSelected, proxy: proxy) }
        })
    }

    /// A search with stops or a return: one page of trains per leg, side by
    /// side like a carousel. Picking a train slides on to the next page, and
    /// once the last is picked the rest fall away to leave the one journey.
    var chooseLegsView: some View {
        withSolutionTools(GeometryReader { geometry in
            // the finished journey is one more page, after the last leg's
            let shownPage = combinedSolution == nil ? legPage : searchedLegs.count

            ZStack {
                ForEach(searchedLegs.indices, id: \.self) { page in
                    legPage(page)
                        // a page's trains hang on the one picked before it, so a
                        // different pick there starts the page afresh
                        .id(legChoices.indices.contains(page - 1) ? legChoices[page - 1].id : nil)
                        .offset(x: CGFloat(page - shownPage) * geometry.size.width)
                        .allowsHitTesting(page == shownPage)
                        .accessibilityHidden(page != shownPage)
                }

                // always there, off to the side, so its days are already in
                // place as it slides in; empty until the last train is picked
                journeySummary
                    .offset(x: CGFloat(searchedLegs.count - shownPage) * geometry.size.width)
                    .allowsHitTesting(combinedSolution != nil)
                    .accessibilityHidden(combinedSolution == nil)
            }
        })
    }

    /// Pages stay alive while off screen, so coming back to one finds it
    /// scrolled exactly where it was left.
    private func legPage(_ page: Int) -> some View {
        let leg = searchedLegs[page]
        let solutions = solutions(onPage: page)
        let state = listState(onPage: page)
        let visible = visibleSolutions(onPage: page)
        let previous = legChoices.indices.contains(page - 1) ? legChoices[page - 1] : nil

        return ScrollViewReader { proxy in
            solutionList(
                showsNoMatches: visible.isEmpty && !solutions.isEmpty,
                searchText: state.searchText
            ) {
                Section {
                    ForEach(visible) { solution in
                        // nothing stays highlighted: a tap moves straight on
                        solutionRow(
                            solution,
                            isSelected: false,
                            expandedID: state.expandedID,
                            rankedAmong: visible
                        ) {
                            pick(solution, onPage: page)
                        }
                    }
                } header: {
                    legHeader(from: leg.origin, to: leg.destination)
                }
            }
            // a later page is rebuilt whenever the train before it changes, so
            // this runs again once there's something to scroll to
            .onAppear { scrollToNextSolution(in: solutions, after: leg.date, proxy: proxy) }
        }
        // the trains picked so far stay put while this page scrolls under them
        .safeAreaBar(edge: .top) {
            if page > 0 { pickedSoFar(beforePage: page) }
        }
        .overlay {
            if let previous, solutions.isEmpty {
                ContentUnavailableView(
                    "No trains onward",
                    systemImage: "moon.zzz",
                    description: Text("Nothing leaves \(leg.origin) after \(previous.arrivalTime.formatted(Date.FormatStyle.dateTime.hour().minute())) that day.")
                )
                .foregroundStyle(Color.secondary)
            }
        }
    }

    /// Tapping it goes back a page to change the last train picked.
    @ViewBuilder private func pickedSoFar(beforePage page: Int) -> some View {
        let picked = Array(legChoices.prefix(page))
        if let first = picked.first {
            let journey = picked.dropFirst().reduce(first) { $0.followed(by: $1) }
            SolutionRow(
                solution: journey,
                isExpanded: pickedSoFarExpanded,
                priceRank: nil,
                onToggleExpanded: {
                    HapticFeedback.select()
                    withAnimation(.smooth) { pickedSoFarExpanded.toggle() }
                }
            )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
                .contentShape(.rect(cornerRadius: 26))
                .onTapGesture {
                    guard !isSaving else { return }
                    HapticFeedback.select()
                    move(toPage: page - 1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    /// The finished journey, a section for each day it's travelled on.
    private var journeySummary: some View {
        solutionList(showsNoMatches: false, searchText: "") {
            ForEach(Array(journeyDays.enumerated()), id: \.element.id) { index, day in
                Section {
                    SolutionRow(
                        solution: day,
                        isExpanded: expandedDayIDs.contains(day.id),
                        priceRank: nil,
                        onToggleExpanded: { toggleDayExpanded(day) }
                    )
                    .contentShape(Rectangle())
                    // tapping the journey lets it go, back to the last page's trains
                    .onTapGesture {
                        guard !isSaving else { return }
                        HapticFeedback.select()
                        reopenLastPage()
                    }
                } header: {
                    Text(day.departureTime, format: .dateTime.weekday(.wide).day().month(.wide))
                } footer: {
                    if index == journeyDays.count - 1, combinedSolution?.ticketFares.count ?? 0 > 1 {
                        Text("Priced as separate tickets.")
                    }
                }
            }
        }
    }

    /// "Torino → Firenze": the first word of each name is the town, which is
    /// all the header needs, and full names like Torino Porta Nuova got cut off.
    private func legHeader(from origin: String, to destination: String) -> some View {
        Text(verbatim: "\(town(origin)) → \(town(destination))")
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func town(_ station: String) -> String {
        station.split(separator: " ").first.map(String.init) ?? station
    }

    private func solutionRow(
        _ solution: Solution,
        isSelected: Bool,
        expandedID: UUID?,
        rankedAmong others: [Solution]?,
        onSelect: @escaping () -> Void
    ) -> some View {
        // while one solution is open the rest recede, so the legs on
        // screen clearly belong to the row you opened
        let isDimmed = expandedID != nil && expandedID != solution.id

        return SolutionRow(
            solution: solution,
            isExpanded: expandedID == solution.id,
            priceRank: others.flatMap { priceRank(for: solution, among: $0) },
            onToggleExpanded: { toggleExpanded(solution) }
        )
        .opacity(isDimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSaving else { return }
            HapticFeedback.select()
            onSelect()
        }
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(isDimmed ? 0.03 : 0.06) : nil
        )
        .id(solution.id)
    }

    private func solutionList<Content: View>(
        showsNoMatches: Bool,
        searchText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List(content: content)
            .listStyle(.insetGrouped)
            // as scroll padding rather than a trailing row, so the last solution
            // keeps the section's rounded bottom corners
            .contentMargins(.bottom, 80, for: .scrollContent)
            .scrollIndicators(.hidden)
            .disabled(isSaving)
            .overlay {
                if showsNoMatches {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "No matching solutions",
                            systemImage: "line.3.horizontal.decrease",
                            description: Text("Clear a filter to see more journeys.")
                        )
                        .foregroundStyle(Color.secondary)
                    } else {
                        ContentUnavailableView.search(text: searchText)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
    }

    /// Search, sort and filter, kept outside the pages so the bottom bar holds
    /// still while the via carousel slides underneath it.
    private func withSolutionTools(_ content: some View) -> some View {
        content
            .searchable(text: $solutionSearchText, prompt: "Search solutions")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    solutionSortMenu.disabled(combinedSolution != nil)
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { solutionFilterMenu }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
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
        label: @escaping (SolutionBucket) -> LocalizedStringKey,
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

    private func filterButton(title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
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
        trips = [[StationEntry(), StationEntry()]]
        stationDrag = nil
        stationSuggestions = []
        stationFetchTask?.cancel()
        prefetchTask?.cancel()
        solutionsFetched = []
        solutionID_selected = nil
        resetLegSelection()
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
            /// with stops or a return, back steps through the pages first
            if isMultiLeg && combinedSolution != nil {
                reopenLastPage()
                return
            }
            if isMultiLeg && legPage > 0 {
                move(toPage: legPage - 1)
                return
            }

            /// update focus
            focusedField = nil
            
            /// change view, taking the results with it so the page leaving keeps them
            go(to: .addTrain) {
                trainsFetched.removeAll()
                trainID_selected = nil
                prefetchTask?.cancel()
                solutionsFetched.removeAll()
                solutionID_selected = nil
                resetLegSelection()
                prefetchedSegments = [:]
                isSaving = false
                fetchState = .idle
            }
            
        case .chooseStops:
            /// change view
            go(to: .chooseTrain) {
                stopsFetched.removeAll()
                stopsSelected.removeAll()
            }
            
        case .chooseDate:
            /// change view
            go(to: .chooseStops) {
                dateSelected = Date()
            }
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
                go(to: .chooseTrain)

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
                guard !isSaving, selectedSolution != nil else { return }

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
                go(to: .chooseStops)

                /// actions
                saveStops()
            }

        case .chooseStops:
            /// haptic feedback
            HapticFeedback.confirm()
            
            /// change view
            go(to: .chooseDate)
            
        case .chooseDate:
            /// haptic feedback
            HapticFeedback.impactHeavy()
            
            /// actions
            saveTrain()
            
            /// change view
            dismiss()
        }
    }

    /// Moves to another step with the same slide as the Choose Train pages.
    /// The direction lands in its own update first, so the step leaving already
    /// carries the transition that matches it; `changes` go with the slide, so
    /// that step keeps showing what it had on its way out. A dispatch to the next
    /// turn wasn't enough: it could land before the first update, and a step
    /// going back then left the way the last one had come in.
    private func go(to step: AddTrainStep, changes: @escaping () -> Void = {}) {
        stepMovesForward = step.order > addTrainStep.order
        // a new search always opens on its placeholder, and one that found
        // nothing leaves on it
        stepFades = (step == .chooseTrain && stepMovesForward)
            || (addTrainStep == .chooseTrain && fetchState != .success)
        stepRequestChanges = changes
        stepRequest = StepRequest(step: step)
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
        withAnimation(.smooth) {
            // opening one closes whichever was open
            expandedSolutionID = expandedSolutionID == solution.id ? nil : solution.id
        }
    }

    private func toggleDayExpanded(_ day: Solution) {
        guard day.segments.count > 1 else { return }
        HapticFeedback.select()
        withAnimation(.smooth) {
            if expandedDayIDs.remove(day.id) == nil { expandedDayIDs.insert(day.id) }
        }
    }

    private func pick(_ solution: Solution, onPage page: Int) {
        // a different train here can change which ones are catchable after it
        if legChoices.indices.contains(page), legChoices[page].id != solution.id {
            pageStates = pageStates.filter { $0.key <= page }
        }
        legChoices = Array(legChoices.prefix(page)) + [solution]

        if page == searchedLegs.count - 1 {
            showJourney()
        } else {
            move(toPage: page + 1)
        }
    }

    private func move(toPage page: Int) {
        pageStates[legPage] = liveListState
        apply(pageStates[page] ?? SolutionListState())
        withAnimation(.snappy) {
            legPage = page
            // each page opens on the trains before it folded up
            pickedSoFarExpanded = false
        }
    }

    /// Every train is picked: the rest fall away to leave the one journey.
    private func showJourney() {
        guard let first = legChoices.first else { return }
        let journey = legChoices.dropFirst().reduce(first) { $0.followed(by: $1) }
        // trains leaving on the same day share a section; one that runs past
        // midnight stays with the day it left on
        var days: [Solution] = []
        for choice in legChoices {
            if let last = days.last,
               Calendar.current.isDate(last.departureTime, inSameDayAs: choice.departureTime) {
                days[days.count - 1] = last.followed(by: choice)
            } else {
                days.append(choice)
            }
        }
        pageStates[legPage] = liveListState
        journeyDays = days
        withAnimation(.snappy) {
            combinedSolution = journey
            // open, so the time at each stop shows between the trains
            expandedDayIDs = Set(days.filter { $0.segments.count > 1 }.map(\.id))
        }
        // starts resolving the trains while the journey is looked over
        solutionID_selected = journey.id
    }

    /// Back from the finished journey to the last page's trains.
    private func reopenLastPage() {
        withAnimation(.snappy) {
            combinedSolution = nil
            apply(pageStates[legPage] ?? SolutionListState())
        }
        solutionID_selected = nil
    }

    private func apply(_ state: SolutionListState) {
        solutionSearchText = state.searchText
        solutionFilters = state.filters
        solutionSort = state.sort
        expandedSolutionID = state.expandedID
    }

    private func resetLegSelection() {
        searchedLegs = []
        legsFetched = []
        legChoices = []
        legPage = 0
        pageStates = [:]
        combinedSolution = nil
        journeyDays = []
        pickedSoFarExpanded = false
        expandedSolutionID = nil
    }

    private var firstStationField: FocusField? {
        trips.first?.first.map { .station($0.id) }
    }

    /// Which trip a station is in, and where.
    private func position(of id: UUID) -> (trip: Int, index: Int)? {
        for (trip, stations) in trips.enumerated() {
            if let index = stations.firstIndex(where: { $0.id == id }) { return (trip, index) }
        }
        return nil
    }

    /// A station's text. Only typing goes through it, so it's where the station
    /// loses its resolved code and looks for new suggestions.
    private func stationBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { position(of: id).map { trips[$0.trip][$0.index].name } ?? "" },
            set: { newValue in
                guard let (trip, index) = position(of: id),
                      trips[trip][index].name != newValue else { return }
                trips[trip][index].name = newValue
                trips[trip][index].code = ""
                guard focusedField == .station(id) else { return }
                scheduleStationFetch(query: newValue, field: .station(id))
            }
        )
    }

    private func addStop(trip: Int, at index: Int) {
        guard trips[trip].count == 2 else { return }
        HapticFeedback.tap()
        let stop = StationEntry()
        withAnimation(.snappy) { trips[trip].insert(stop, at: index) }
        focusedField = .station(stop.id)
    }

    private func removeStop(trip: Int, at index: Int) {
        HapticFeedback.tap()
        if focusedField == .station(trips[trip][index].id) {
            focusedField = nil
        }
        withAnimation(.snappy) { _ = trips[trip].remove(at: index) }
    }

    /// A stop left empty is one the user changed their mind about, so it goes
    /// once they move on. Departure and arrival always stay.
    private func removeIfEmptyStop(_ field: FocusField) {
        guard case .station(let id) = field,
              let (trip, index) = position(of: id),
              trips[trip].count > 2,
              index > 0, index < trips[trip].count - 1,
              trips[trip][index].name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.snappy) { _ = trips[trip].remove(at: index) }
    }

    /// The return can't be picked before the outbound.
    private func returnRange(_ trip: Int) -> PartialRangeFrom<Date> {
        (trip == 0 ? Date.distantPast : dateSelected)...
    }

    /// The way back: the outbound's arrival to its departure, the next day at
    /// the same time.
    private func addReturn() {
        HapticFeedback.tap()
        let outbound = trips[0]
        let back = [outbound.last, outbound.first].map {
            StationEntry(name: $0?.name ?? "", code: $0?.code ?? "")
        }
        returnDate = Calendar.current.date(byAdding: .day, value: 1, to: dateSelected) ?? dateSelected
        withAnimation(.snappy) { trips.append(back) }
    }

    /// Return on a station moves on to the next one, and on the very last runs the search.
    private func submitStation(_ id: UUID) {
        if let first = stationSuggestions.first {
            selectStation(first, field: .station(id))
        } else {
            adoptFirstSuggestion(for: .station(id))
            focusedField = field(after: id)
        }
        // every station resolved: go straight on rather than
        // making the user reach for the toolbar button
        if focusedField == nil, buttonIsActive { nextButtonAction() }
    }

    /// The row below, running on into the return; nil after the last.
    private func field(after id: UUID) -> FocusField? {
        let all = trips.flatMap { $0 }
        guard let index = all.firstIndex(where: { $0.id == id }), index + 1 < all.count else { return nil }
        return .station(all[index + 1].id)
    }

    /// Places a fare on the green-to-red ramp against the others on screen.
    private func priceRank(for solution: Solution, among others: [Solution]) -> SolutionPriceRank? {
        guard let price = solution.price else { return nil }
        let prices = others.compactMap(\.price)
        guard let cheapest = prices.min(), let priciest = prices.max(), cheapest < priciest else { return nil }
        return SolutionPriceRank(position: (price - cheapest) / (priciest - cheapest))
    }

    // on open, jump straight to the next departure from now so the user can catch it
    /// Opens the list on the first train leaving at or after the time asked for.
    private func scrollToNextSolution(in solutions: [Solution], after time: Date, proxy: ScrollViewProxy) {
        guard let target = solutions.first(where: { $0.departureTime >= time }) else { return }

        DispatchQueue.main.async {
            proxy.scrollTo(target.id, anchor: .top)
        }
    }

    private func minutesBetween(_ start: Date, _ end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start)) / 60)
    }

    private func stationText(for field: FocusField) -> String {
        switch field {
        case .station(let id): return stationBinding(id).wrappedValue
        case .number: return trainNumber
        }
    }

    /// Looks the stations nearby up once, the first time the departure is edited.
    private func loadNearbyStations() {
        guard nearbyStationsTask == nil, nearbyStations.isEmpty else { return }
        nearbyStationsTask = Task {
            nearbyStations = await NearbyStations.suggestions { name in
                StationBoardAPI.best(for: name, among: await TrenitaliaAPI().stationAutocomplete(name: name))
            }
        }
    }

    private func scheduleStationFetch(for field: FocusField) {
        let query = stationText(for: field)
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
            guard stationText(for: field) == query else { return }
            stationSuggestions = results
        }
    }

    /// Commits the top suggestion for a field the user typed into but never
    /// picked from, so the code needed to fetch solutions is still filled in.
    private func adoptFirstSuggestion(for field: FocusField) {
        guard let match = stationSuggestions.first else { return }

        guard case .station(let id) = field,
              let (trip, index) = position(of: id),
              trips[trip][index].code.isEmpty,
              !trips[trip][index].name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        trips[trip][index].name = match.name
        trips[trip][index].code = match.code
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
        guard case .station(let id) = field, let (trip, index) = position(of: id) else { return }
        trips[trip][index].name = station.name
        trips[trip][index].code = station.code
        focusedField = self.field(after: id)
    }

    private func fetchSolutions() async {
        fetchState = .fetching

        let legs = journeyLegs
        guard isMultiLeg else {
            guard let leg = legs.first else {
                await MainActor.run { fetchState = .failure }
                return
            }
            let results = await Self.solutions(for: leg)

            await MainActor.run {
                solutionsFetched = results
                fetchState = results.isEmpty ? .failure : .success
            }
            return
        }

        // every leg at once: the later ones are only narrowed down to what's
        // catchable once the train before them is picked
        let results = await withTaskGroup(of: (Int, [Solution]).self) { group in
            for (index, leg) in legs.enumerated() {
                group.addTask { (index, await Self.solutions(for: leg)) }
            }
            var byIndex: [Int: [Solution]] = [:]
            for await (index, solutions) in group { byIndex[index] = solutions }
            return legs.indices.map { byIndex[$0] ?? [] }
        }

        await MainActor.run {
            resetLegSelection()
            solutionID_selected = nil
            searchedLegs = legs
            legsFetched = results
            fetchState = results.contains(where: \.isEmpty) ? .failure : .success
        }
    }

    /// Trenitalia's journeys for one leg, with Italo's direct trains among them
    /// when Italo serves both ends.
    private static func solutions(for leg: JourneyLeg) async -> [Solution] {
        async let trenitalia = TrenitaliaAPI().trainSolutions(
            departureLocationId: leg.originCode,
            arrivalLocationId: leg.destinationCode,
            departureTime: leg.date
        )
        async let italo = ItaloAPI().trainSolutions(
            origin: leg.origin,
            departureLocationId: leg.originCode,
            destination: leg.destination,
            arrivalLocationId: leg.destinationCode,
            departureTime: leg.date
        )
        return (await trenitalia + italo).sorted { $0.departureTime < $1.departureTime }
    }

    // saves the selected solution: each leg becomes its own train, so connected
    // journeys render with the connection manager just like in TodayView.
    private func saveSolution() async {
        guard let solution = selectedSolution else {
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
            let journeyID = preparedSegments.count > 1 ? UUID() : nil
            for prepared in preparedSegments {
                saveSegment(prepared, journeyID: journeyID)
            }
            try? modelContext.save()
            reloadWidgetTimelines()
            isSaving = false
        }
    }

    private func saveSegment(_ prepared: PreparedSolutionSegment, journeyID: UUID?) {
        let id = UUID()
        let info = prepared.info
        let dayOffset = prepared.dayOffset

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
            issue: info["issue"] as? String ?? "",
            journeyID: journeyID
        )
        modelContext.insert(train)

        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.map { $0["name"] as? String ?? "" }
        // lefrecce and viaggiatreno don't always name a station alike ("Firenze
        // S. M. Novella" against "Firenze Santa Maria Novella"), so a stop the name
        // can't find is the one the train leaves, or reaches, at the searched time
        func index(of time: Date, _ key: String) -> Int? {
            stops.firstIndex { stop in
                guard let scheduled = stop[key] as? Date else { return false }
                return abs(offsetDate(scheduled).timeIntervalSince(time)) < 60
            }
        }
        let fromIdx = names.firstIndex(of: prepared.fromStation) ?? index(of: prepared.departureTime, "dep_time_id")
        let toIdx = names.firstIndex(of: prepared.toStation) ?? index(of: prepared.arrivalTime, "arr_time_id")

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
        self._trips = State(initialValue: [[StationEntry(name: departureStation), StationEntry()]])
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
        .environment(\.locale, Locale(identifier: "it"))
}
