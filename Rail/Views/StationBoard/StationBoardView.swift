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

    @State private var stationText = ""
    @State private var station: StationSuggestion?
    @State private var kind: StationBoardKind = .departures

    @State private var suggestions: [StationSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>?
    @State private var isAdoptingSuggestion = false
    @State private var hasResolvedInitialStation = false

    @State private var board: [BoardTrain] = []
    @State private var isLoadingBoard = false

    @FocusState private var isEditingStation: Bool

    // MARK: - Computed

    /// Restarts the board whenever the station or the side of it changes.
    private var boardKey: String { "\(station?.code ?? "")|\(kind.rawValue)" }

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
            // collapse into the toolbar
            .searchable(
                text: $stationText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Station"
            )
            .searchFocused($isEditingStation)
            .onSubmit(of: .search) { adoptFirstSuggestion() }
            .navigationTitle(station?.name ?? String(localized: "Timetable"))
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
                if isEditingStation, !suggestions.isEmpty {
                    StationSuggestionsBar(suggestions: suggestions, onSelect: select)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: suggestions)
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
        .onChange(of: isEditingStation) { _, isEditing in
            guard !isEditing else { return }
            // leaving the field still counts as choosing what was typed
            if station == nil { adoptFirstSuggestion() }
            suggestions = []
        }
        .task(id: boardKey) {
            guard let code = station?.code else { return }

            isLoadingBoard = true
            // A board is only ever now, so it keeps itself current for as long as
            // it is on screen.
            while !Task.isCancelled {
                let results = await StationBoardAPI.board(kind, at: code)
                guard !Task.isCancelled else { return }
                board = results
                isLoadingBoard = false
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
                systemImage: "arrow.up",
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
