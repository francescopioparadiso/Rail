import SwiftUI
import SwiftData

/// The board a station itself would show: everything leaving from, or arriving at,
/// one station right now.
///
/// It is the way into a journey that wasn't planned — you are at the station, you
/// see what is due, and you keep the one you are about to catch.
struct StationBoardView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    /// A station to open straight onto, named as a journey names it. Set when the
    /// board is reached from a stop rather than from the toolbar.
    var initialStation: String? = nil

    /// The moment this stop's own timetable is built around, in place of now. Set
    /// alongside `initialStation`: a stop already past, or hours off, still wants the
    /// board as it read at its own arrival — not whatever the board reads at the
    /// moment the sheet happens to be opened.
    var referenceDate: Date? = nil

    @State private var stationText = ""
    @State private var station: StationSuggestion?
    @State private var kind: StationBoardKind

    @State private var suggestions: [StationSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>?
    /// The stations around the user, offered while nothing has been typed.
    @State private var nearbyStations: [StationSuggestion] = []
    @State private var isAdoptingSuggestion = false
    @State private var hasResolvedInitialStation = false

    @State private var board: [BoardTrain] = []
    @State private var isLoadingBoard = false

    /// The moments each further stretch of the board was asked for. The feed only
    /// answers about an hour and a half at a time, so scrolling to the end asks for
    /// the next stretch, starting from the last train already listed.
    @State private var laterPageDates: [Date] = []
    @State private var isLoadingMore = false
    /// Bumped each time a further stretch has come in, so the row at the end of the
    /// list — if it is still on screen — asks for the one after.
    @State private var loadedPages = 0

    @FocusState private var isEditingStation: Bool

    init(initialStation: String? = nil, referenceDate: Date? = nil) {
        self.initialStation = initialStation
        self.referenceDate = referenceDate
        // A stop's own board reads as the connection onward from it, so it opens on
        // departures even though the picker still lists arrivals first.
        _kind = State(initialValue: referenceDate == nil ? .arrivals : .departures)
    }

    // MARK: - Computed

    /// Restarts the board whenever the station or the side of it changes.
    private var boardKey: String { "\(station?.code ?? "")|\(kind.rawValue)" }

    /// Reloads the board when a further stretch is asked for, as well.
    private var boardTaskKey: String { "\(boardKey)|\(laterPageDates.count)" }

    /// The moment the board starts from: the stop's own for a stop's timetable,
    /// now otherwise.
    private var boardStart: Date { referenceDate ?? Date() }

    /// No more than a day ahead is ever asked for.
    private static let boardHorizon: TimeInterval = 24 * 3600

    /// How far each stretch of the feed reaches past the moment it is asked for.
    private static let pageSpan: TimeInterval = 90 * 60

    /// Where the next stretch would start: the last train listed, or a full stretch
    /// on when the last one came back with nothing new. Italo's trains don't count:
    /// its board reaches past the stretch, and would skip what lies in between.
    private var nextPageDate: Date {
        let lastAsked = laterPageDates.last ?? boardStart
        let latest = board.filter { !$0.isItalo }.map(\.scheduledTime).max() ?? lastAsked
        return latest > lastAsked ? latest : lastAsked.addingTimeInterval(Self.pageSpan)
    }

    private var canLoadMore: Bool {
        nextPageDate < boardStart.addingTimeInterval(Self.boardHorizon)
    }

    private var showsNearbyStations: Bool {
        stationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the suggestion bar offers: the stations nearby on an empty field,
    /// matches for the text otherwise.
    private var displayedSuggestions: [StationSuggestion] {
        showsNearbyStations ? nearbyStations : suggestions
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if station != nil {
                    kindPicker
                }

                boardContent
            }
            // the system search field, pinned under the title rather than left to
            // collapse into the toolbar — absent for a stop's own board, which
            // already knows its station and has nothing to search for
            .applyingIf(referenceDate == nil) {
                $0.searchable(
                    text: $stationText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Station"
                )
                .searchFocused($isEditingStation)
                .onSubmit(of: .search) { adoptFirstSuggestion() }
            }
            // A station name is data and the fallback is a phrase, so each is passed
            // as the kind of Text it actually is.
            .navigationTitle(station.map { Text(verbatim: $0.name) } ?? Text("Timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .background(appBackgroundColor.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationDestination(for: BoardTrain.self) { boardTrain in
                BoardTrainDetailView(
                    boardTrain: boardTrain,
                    station: station?.name ?? "",
                    kind: kind
                )
            }
            // sits above the keyboard while a station is being typed, exactly as
            // it does in the Add Train form
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEditingStation, !displayedSuggestions.isEmpty {
                    StationSuggestionsBar(
                        suggestions: displayedSuggestions,
                        isNearby: showsNearbyStations,
                        onSelect: select
                    )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: displayedSuggestions)
            .animation(.snappy, value: station)
            // .container only: ignoring the keyboard region too would leave the
            // station suggestion bar stranded behind the keyboard
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear {
            // nothing to type when the station is already known
            guard initialStation == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isEditingStation = true
            }
        }
        .task { await resolveInitialStation() }
        .task {
            // a stop's own board has its station already
            guard initialStation == nil else { return }
            nearbyStations = await NearbyStations.suggestions { name in
                await StationBoardAPI.station(named: name)
            }
        }
        .onDisappear { suggestionTask?.cancel() }
        .onChange(of: stationText) { _, newValue in
            // choosing a suggestion writes the field itself; everything else is
            // the user typing, which unpicks the station they had
            if isAdoptingSuggestion {
                isAdoptingSuggestion = false
                return
            }
            station = nil
            board = []
            scheduleSuggestions(for: newValue)
        }
        .onChange(of: boardKey) {
            // a different station, or the other side of it, starts from its first stretch
            laterPageDates = []
            isLoadingMore = false
            board = []
        }
        .onChange(of: isEditingStation) { _, isEditing in
            guard !isEditing else { return }
            // leaving the field still counts as choosing what was typed
            if station == nil { adoptFirstSuggestion() }
            suggestions = []
        }
        .task(id: boardTaskKey) {
            guard let code = station?.code else { return }

            if board.isEmpty { isLoadingBoard = true }
            // A board is only ever now, so it keeps itself current for as long as
            // it is on screen — unless it was opened as a stop's own timetable, which
            // stays anchored to that stop's moment rather than drifting to the
            // device's clock. Every stretch scrolled to is refreshed along with the
            // first, so a delay further down the list is kept up to date too.
            while !Task.isCancelled {
                let results = await fetchBoard(at: code, from: boardStart, laterPages: laterPageDates)
                guard !Task.isCancelled else { return }
                board = results
                isLoadingBoard = false
                if isLoadingMore {
                    isLoadingMore = false
                    loadedPages += 1
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Subviews

    private var kindPicker: some View {
        Picker("Board", selection: $kind) {
            ForEach(StationBoardKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var boardContent: some View {
        if station == nil {
            boardPlaceholder(
                "Choose a station",
                systemImage: "magnifyingglass",
                description: "Search for a station to see the trains due there."
            )
        } else if isLoadingBoard {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if board.isEmpty {
            boardPlaceholder(
                "No trains",
                systemImage: "clock.badge.xmark",
                description: "Nothing is due here over the next couple of hours."
            )
        } else {
            List {
                ForEach(board) { boardTrain in
                    NavigationLink(value: boardTrain) {
                        StationBoardRow(train: boardTrain)
                    }
                }

                if canLoadMore {
                    // Reaching the end of the list asks for the next stretch; so
                    // does a stretch coming in that still leaves this row on screen.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .task(id: loadedPages) { loadMore() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
    }

    private func boardPlaceholder(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .foregroundStyle(Color.secondary)
            .fontDesign(appFontDesign)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func select(_ suggestion: StationSuggestion) {
        HapticFeedback.select()
        isAdoptingSuggestion = true
        stationText = suggestion.name
        station = suggestion
        suggestions = []
        isEditingStation = false
    }

    private func loadMore() {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        laterPageDates.append(nextPageDate)
    }

    /// The first stretch and every later one, together: each train once, in the
    /// order it will call. The stretches overlap, so a train can come back twice.
    /// Italo's trains join them on a board read for now — its own board is only
    /// ever now, so a stop's timetable set at another time goes without.
    private func fetchBoard(at code: String, from start: Date, laterPages: [Date]) async -> [BoardTrain] {
        let dates = [start] + laterPages
        let includesItalo = abs(start.timeIntervalSinceNow) < Self.pageSpan
        let pages = await withTaskGroup(of: (Int, [BoardTrain]).self) { group in
            for (index, date) in dates.enumerated() {
                group.addTask { (index, await StationBoardAPI.board(kind, at: code, on: date)) }
            }
            if includesItalo {
                group.addTask { (dates.count, await StationBoardAPI.italoBoard(kind, at: code, on: start)) }
            }
            var byIndex: [Int: [BoardTrain]] = [:]
            for await (index, trains) in group {
                byIndex[index] = trains
            }
            return byIndex
        }

        var seen: Set<String> = []
        return (0...dates.count)
            .flatMap { pages[$0] ?? [] }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.effectiveTime < $1.effectiveTime }
    }

    private func adoptFirstSuggestion() {
        guard let first = suggestions.first else { return }
        select(first)
    }

    /// Turns the name a journey gave us into a station the boards will answer for.
    private func resolveInitialStation() async {
        guard let initialStation, !hasResolvedInitialStation else { return }
        hasResolvedInitialStation = true

        guard let match = await StationBoardAPI.station(named: initialStation) else { return }

        isAdoptingSuggestion = true
        stationText = match.name
        station = match
    }

    private func scheduleSuggestions(for query: String) {
        suggestionTask?.cancel()

        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            suggestions = []
            return
        }

        suggestionTask = Task(priority: .userInitiated) {
            let results = await StationBoardAPI.stations(matching: query)
            guard !Task.isCancelled, stationText == query else { return }
            suggestions = results
        }
    }
}

#Preview("Station Board") {
    let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, UserProfile.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            StationBoardView()
                .modelContainer(container)
        }
}
