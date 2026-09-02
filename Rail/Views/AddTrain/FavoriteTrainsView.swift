import SwiftUI
import SwiftData

enum PreloadState: Equatable {
    case loading
    case ready
    case unavailable
}

struct FavoriteTrainsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Favorite.index) private var favorites: [Favorite]
    @Query private var profiles: [UserProfile]

    @Binding var preloadStates: [UUID: PreloadState]
    @Binding var preparedTrains: [UUID: PreparedFavoriteTrain]
    var onTrainAdded: (() -> Void)? = nil

    @State private var searchText = ""

    private var filteredFavorites: [Favorite] {
        favorites.filter { matches($0, searchText: searchText) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No favorites yet",
                        systemImage: "heart",
                        description: Text("Save a train as a favorite from its details page.")
                    )
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                } else if isSearching && filteredFavorites.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(Color.secondary)
                        .fontDesign(appFontDesign)
                } else {
                    List {
                        ForEach(filteredFavorites) { favorite in
                            favoriteRow(favorite)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .contentMargins(.bottom, 80, for: .scrollContent)
                    .scrollIndicators(.visible)
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .searchable(text: $searchText, prompt: "Search favorites")
        }
        .background(appBackgroundColor.ignoresSafeArea())
    }

    @ViewBuilder
    private func favoriteRow(_ favorite: Favorite) -> some View {
        let state = preloadStates[favorite.id] ?? .loading

        FavoriteTrainCard(
            favorite: favorite,
            isLoading: state == .loading,
            isUnavailable: state == .unavailable
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // a favorite is already fully resolved by the time it's tappable,
            // so there is nothing left to confirm
            guard state == .ready else { return }
            addFavorite(favorite.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteFavorite(favorite)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func addFavorite(_ favoriteID: UUID) {
        guard preloadStates[favoriteID] == .ready,
              let prepared = preparedTrains[favoriteID] else { return }

        HapticFeedback.confirm()
        FavoriteTrainService.savePreparedTrain(
            prepared,
            modelContext: modelContext,
            profile: profiles.primary
        )
        onTrainAdded?()
        dismiss()
    }

    private func deleteFavorite(_ favorite: Favorite) {
        HapticFeedback.confirm()

        modelContext.delete(favorite)

        let remaining = favorites
            .filter { $0.id != favorite.id }
            .sorted { $0.index < $1.index }

        for (index, item) in remaining.enumerated() {
            item.index = index
        }

        try? modelContext.save()
    }

    private func matches(_ favorite: Favorite, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableFields = [
            favorite.number,
            favorite.identifier,
            favorite.provider,
            favorite.logo
        ] + favorite.stop_names

        return searchableFields.contains { $0.lowercased().contains(query) }
    }
}

#Preview("Favorite Trains View") {
    let schema = Schema([Favorite.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext

    func time(_ hour: Int, _ min: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: min, second: 0, of: Date()) ?? .distantPast
    }

    let fav1ID = UUID()
    let fav2ID = UUID()
    let fav3ID = UUID()
    let fav4ID = UUID()

    let favorites = [
        Favorite(
            id: fav1ID, index: 0, identifier: "IT9904", provider: "italo", logo: "ITALO", number: "9904",
            stop_names: ["Roma Termini", "Milano Centrale"], stop_ref_times: [time(6, 20), time(8, 46)]
        ),
        Favorite(
            id: fav2ID, index: 1, identifier: "REG3224", provider: "trenitalia", logo: "REG", number: "3224",
            stop_names: ["Cuneo", "Carmagnola"], stop_ref_times: [time(9, 24), time(10, 9)]
        ),
        Favorite(
            id: fav3ID, index: 2, identifier: "FR9612", provider: "trenitalia", logo: "FR", number: "9612",
            stop_names: ["Milano Centrale", "Roma Termini"], stop_ref_times: [time(7, 0), time(10, 0)]
        ),
        Favorite(
            id: fav4ID, index: 3, identifier: "IC605", provider: "trenitalia", logo: "IC", number: "605",
            stop_names: ["Torino Porta Nuova", "Genova Piazza Principe"], stop_ref_times: [time(14, 15), time(16, 40)]
        )
    ]
    favorites.forEach { context.insert($0) }

    let preloadStates: [UUID: PreloadState] = [
        fav1ID: .ready,
        fav2ID: .loading,
        fav3ID: .unavailable,
        fav4ID: .ready
    ]
    let preparedTrains: [UUID: PreparedFavoriteTrain] = [
        fav1ID: PreparedFavoriteTrain(info: [:], fromStation: "Roma Termini", toStation: "Milano Centrale"),
        fav4ID: PreparedFavoriteTrain(info: [:], fromStation: "Torino Porta Nuova", toStation: "Genova Piazza Principe")
    ]

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            FavoriteTrainsView(
                preloadStates: .constant(preloadStates),
                preparedTrains: .constant(preparedTrains)
            )
            .modelContainer(container)
        }
}

#Preview("Favorite Trains View - Empty") {
    let schema = Schema([Favorite.self, UserProfile.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            FavoriteTrainsView(
                preloadStates: .constant([:]),
                preparedTrains: .constant([:])
            )
            .modelContainer(container)
        }
}
