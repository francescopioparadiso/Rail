import SwiftUI
import SwiftData

enum PreloadState: Equatable {
    case loading
    case ready
    case unavailable
}

enum FavoriteRowStrokeAppearance {
    case loading
    case ready
    case unavailable
    case selected
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
    @State private var selectedFavoriteID: UUID?

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
                    .fontDesign(app_font_design)
                } else if isSearching && filteredFavorites.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .fontDesign(app_font_design)
                } else {
                    List {
                        ForEach(Array(filteredFavorites.enumerated()), id: \.element.id) { index, favorite in
                            favoriteRow(favorite, index: index, totalCount: filteredFavorites.count)
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal)
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

                ToolbarItem(placement: .topBarTrailing) {
                    if let selectedFavoriteID,
                       preloadStates[selectedFavoriteID] == .ready,
                       preparedTrains[selectedFavoriteID] != nil {
                        Button {
                            confirmAdd(selectedFavoriteID)
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .searchable(text: $searchText, prompt: "Search favorites")
        }
        .background(app_background_color.ignoresSafeArea())
    }

    @ViewBuilder
    private func favoriteRow(_ favorite: Favorite, index: Int, totalCount: Int) -> some View {
        let state = preloadStates[favorite.id] ?? .loading
        let stroke = strokeAppearance(for: favorite, state: state)

        FavoriteTrainCard(
            favorite: favorite,
            strokeAppearance: stroke
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectFavorite(favorite, state: state)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.top, index == 0 ? 16 : 24)
        .padding(.bottom, index == totalCount - 1 ? 24 : 0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteFavorite(favorite)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func strokeAppearance(for favorite: Favorite, state: PreloadState) -> FavoriteRowStrokeAppearance {
        if selectedFavoriteID == favorite.id, state == .ready {
            return .selected
        }

        switch state {
        case .loading:
            return .loading
        case .ready:
            return .ready
        case .unavailable:
            return .unavailable
        }
    }

    private func selectFavorite(_ favorite: Favorite, state: PreloadState) {
        guard state == .ready else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedFavoriteID = favorite.id
    }

    private func confirmAdd(_ favoriteID: UUID) {
        guard preloadStates[favoriteID] == .ready,
              let prepared = preparedTrains[favoriteID] else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        FavoriteTrainService.savePreparedTrain(
            prepared,
            modelContext: modelContext,
            profile: profiles.first
        )
        onTrainAdded?()
        dismiss()
    }

    private func deleteFavorite(_ favorite: Favorite) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if selectedFavoriteID == favorite.id {
            selectedFavoriteID = nil
        }

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

struct FavoriteTrainCard: View {
    let favorite: Favorite
    let strokeAppearance: FavoriteRowStrokeAppearance

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(favorite.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                Text(favorite.number)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(favorite.stop_names.first ?? "")
                    Spacer()
                    if let time = favorite.stop_ref_times.first {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
                HStack {
                    Text(favorite.stop_names.last ?? "")
                    Spacer()
                    if let time = favorite.stop_ref_times.last {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
        }
        .fontDesign(app_font_design)
        .foregroundStyle(Color.primary)
        .padding()
        .contentShape(Rectangle())
        .background {
            FavoriteTrainCardBorder(appearance: strokeAppearance)
        }
    }
}

private struct FavoriteTrainCardBorder: View {
    let appearance: FavoriteRowStrokeAppearance

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: 24, style: .continuous).inset(by: 0.5)
    }

    var body: some View {
        switch appearance {
        case .loading:
            TimelineView(.animation) { context in
                let phase = CGFloat((context.date.timeIntervalSinceReferenceDate * 3).truncatingRemainder(dividingBy: 1)) * 12
                shape.stroke(
                    Color.secondary,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6], dashPhase: phase)
                )
            }
        case .ready:
            shape.stroke(
                Color.secondary,
                style: StrokeStyle(lineWidth: 1, dash: [5])
            )
        case .unavailable:
            shape.stroke(Color.red, lineWidth: 1.5)
        case .selected:
            shape.stroke(Color.blue, lineWidth: 2)
        }
    }
}
