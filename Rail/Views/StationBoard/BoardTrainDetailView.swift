import SwiftUI
import SwiftData

/// A train opened from a station board, which does not belong to the app.
///
/// The board knows only an identifier, so the journey is resolved on the way in and
/// staged in a throwaway in-memory store. That store, not the app's database, is
/// what the details screen reads and writes, so a train can be browsed — refreshing
/// as it runs, like any other — and leave nothing behind when it is closed.
struct BoardTrainDetailView: View {
    // MARK: - Properties

    let boardTrain: BoardTrain
    let station: String
    let kind: StationBoardKind
    @State private var journey: StagedJourney?
    @State private var didFail = false

    // MARK: - Body

    var body: some View {
        Group {
            if let journey {
                DetailsView(
                    train: journey.train,
                    showTicketInitially: .constant(false),
                    ticketSeatID: .constant(nil),
                    isPreview: true
                )
                .modelContainer(journey.container)
            } else if didFail {
                ContentUnavailableView(
                    "Train unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("This train's route couldn't be loaded. Check your connection and try again.")
                )
                .foregroundStyle(Color.secondary)
                .fontDesign(appFontDesign)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .task { await resolve() }
    }

    // MARK: - Actions

    private func resolve() async {
        guard journey == nil, !didFail else { return }

        guard let info = await TrenitaliaAPI().info(identifier: boardTrain.id, shouldFetchWeather: false),
              let staged = stage(info) else {
            didFail = true
            return
        }

        journey = staged
    }

    /// Turns the resolved journey into a train sitting in its own store, riding
    /// from the station being looked at to the end of the line — or, on an arrivals
    /// board, from the start of the line to here.
    private func stage(_ info: [String: Any]) -> StagedJourney? {
        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.map { $0["name"] as? String ?? "" }
        guard let origin = names.first, let terminus = names.last else { return nil }

        let boarded = boardedStop(in: stops, names: names)
        let from = kind == .departures ? (boarded ?? origin) : origin
        let to = kind == .departures ? terminus : (boarded ?? terminus)

        guard let container = PreviewJourneyStore.container else { return nil }

        let journey = PreparedFavoriteTrain(info: info, fromStation: from, toStation: to)
        let (train, _) = FavoriteTrainService.insert(journey, into: container.mainContext)
        try? container.mainContext.save()

        return StagedJourney(container: container, train: train)
    }

    /// Which stop on the route is the one whose board this is. Both endpoints draw
    /// on the same station list so the names line up, but the time the board quotes
    /// settles it if they ever don't.
    private func boardedStop(in stops: [[String: Any]], names: [String]) -> String? {
        if let match = names.first(where: { $0.caseInsensitiveCompare(station) == .orderedSame }) {
            return match
        }

        let key = kind == .departures ? "dep_time_id" : "arr_time_id"
        let index = stops.firstIndex { stop in
            guard let time = stop[key] as? Date else { return false }
            return abs(time.timeIntervalSince(boardTrain.scheduledTime)) < 60
        }
        return index.map { names[$0] }
    }
}

/// The store every previewed journey lives in, made once and shared.
///
/// One store per journey was the obvious thing to write and it crashes: Core Data
/// hands out a connection for the first in-memory container and throws
/// "No eligible connection available" on the second, taking the app with it the
/// moment a second train is opened from a board. Nothing here needed more than one
/// store anyway — a journey is told apart by its own id, not by the store it sits
/// in. Journeys accumulate in memory for the session and go when the app does.
@MainActor
enum PreviewJourneyStore {
    static let container: ModelContainer? = {
        let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, UserProfile.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try? ModelContainer(for: schema, configurations: configuration)
    }()
}

/// A journey staged in that store, ready for the details screen.
private struct StagedJourney {
    let container: ModelContainer
    let train: Train
}
