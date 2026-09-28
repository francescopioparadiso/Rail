import SwiftUI
import SwiftData

/// A train opened from a station board, which does not belong to the app.
///
/// The board knows only an identifier, so the journey is resolved on the way in and
/// staged in a context that is never saved. The details screen reads and writes that
/// context instead of the app's own data, so a train can be browsed — advancing and
/// refreshing as it runs, like any other — and leave nothing behind: nothing on
/// disk, nothing in iCloud, and nothing in the lists.
struct BoardTrainDetailView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    let boardTrain: BoardTrain
    let station: String
    let kind: StationBoardKind

    @State private var journey: Train?
    @State private var didFail = false

    /// The journey as it was resolved, kept so the same mapping that filled the
    /// throwaway store can fill the real one if it is asked for.
    @State private var prepared: PreparedFavoriteTrain?

    // MARK: - Computed

    /// The day this run sets out from its origin, as the board's identifier has it.
    private var runDay: Date? {
        guard !boardTrain.isItalo else { return nil }
        return boardTrain.id.split(separator: "/").last
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Whether the run sets out after today — the board reaches into tomorrow.
    private var isLaterDay: Bool {
        guard let runDay else { return false }
        return runDay > Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            journeyContent
                // Keeps the button clear of the status legend that closes the
                // details screen, the way the stop picker margins its own list.
                .safeAreaPadding(.bottom, journey == nil ? 0 : 76)

            if journey != nil {
                addButton
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
        .task { await resolve() }
    }

    @ViewBuilder
    private var journeyContent: some View {
        Group {
            if let journey {
                DetailsView(
                    train: journey,
                    showTicketInitially: .constant(false),
                    ticketSeatID: .constant(nil),
                    isPreview: true
                )
                .modelContext(PreviewJourneyStore.context(on: modelContext.container))
            } else if didFail {
                ContentUnavailableView(
                    "Train unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(isLaterDay
                        ? "This train doesn't run today, so its route isn't published yet. Try again on the day."
                        : "This train's route couldn't be loaded. Check your connection and try again.")
                )
                .foregroundStyle(Color.secondary)
                .fontDesign(appFontDesign)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// A full-width prominent button resting just above the home indicator, the
    /// way the system places a screen's one primary action.
    private var addButton: some View {
        Button {
            HapticFeedback.confirm()
            save()
        } label: {
            Label("Add to my journeys", systemImage: "plus")
                .font(.headline)
                .fontDesign(appFontDesign)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color.blue)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    /// The one network call this screen makes. A board lists far more trains than
    /// anyone opens, so a route is fetched when a train is actually asked for and
    /// never before.
    private func resolve() async {
        guard journey == nil, !didFail else { return }

        guard let info = await routeInfo(), let staged = stage(info) else {
            didFail = true
            return
        }

        journey = staged
    }

    /// The run the board lists, or — for a run on a later day, which the feed won't
    /// publish until that day — today's run of the same train, moved onto its day.
    private func routeInfo() async -> [String: Any]? {
        // Italo's board only lists today's trains, which its feed has by number
        if boardTrain.isItalo {
            return await ItaloAPI().info(identifier: boardTrain.number, shouldFetchWeather: false)
        }
        if let info = await TrenitaliaAPI().info(identifier: boardTrain.id, shouldFetchWeather: false) {
            return info
        }
        guard isLaterDay, let runDay else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayMilliseconds = Int(today.timeIntervalSince1970 * 1000)
        let todayID = (boardTrain.id.split(separator: "/").dropLast().map(String.init) + [String(todayMilliseconds)])
            .joined(separator: "/")
        guard let info = await TrenitaliaAPI().info(identifier: todayID, shouldFetchWeather: false) else { return nil }

        let dayOffset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: runDay)).day ?? 0
        return EmailTrainService.applyDayOffset(
            to: info,
            dayOffset: dayOffset,
            targetDeparture: runDay,
            calendar: calendar
        )
    }

    /// Moves the journey out of the throwaway store and into the app, with the
    /// calendar event and widget refresh every other way of adding a train gets.
    private func save() {
        guard let prepared else { return }
        let train = FavoriteTrainService.savePreparedTrain(
            prepared,
            modelContext: modelContext,
            profile: profiles.primary
        )
        // Routing closes the board sheet on its way to Today, so don't pop as well:
        // two dismissals in one turn is what left the journey on a blank screen.
        DeepLinkRouter.shared.open(trainID: train.id)
    }

    /// Puts the resolved journey in the preview context, riding from the station
    /// being looked at to the end of the line — or, on an arrivals board, from the
    /// start of the line to here.
    private func stage(_ info: [String: Any]) -> Train? {
        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.map { $0["name"] as? String ?? "" }
        guard let origin = names.first, let terminus = names.last else { return nil }

        let boarded = boardedStop(in: stops, names: names)
        let from = kind == .departures ? (boarded ?? origin) : origin
        let to = kind == .departures ? terminus : (boarded ?? terminus)

        let staged = PreparedFavoriteTrain(info: info, fromStation: from, toStation: to)
        prepared = staged

        let context = PreviewJourneyStore.context(on: modelContext.container)
        let (train, _) = FavoriteTrainService.insert(staged, into: context)
        return train
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

/// Where journeys live while they are only being looked at.
///
/// It is a context on the app's own container, made once, with autosaving off and
/// no save ever asked of it. Objects inserted there are visible to the screen
/// reading that context and to nothing else — not the app's lists, not the store on
/// disk, not iCloud — and they cost a fetch and some memory, no writes at all.
///
/// A container of its own was the obvious thing to write, and it is what crashed:
/// Core Data hands out a connection for the first extra store and throws
/// "No eligible connection available" on the next, killing the app the moment a
/// second train was opened. Sharing the container the app already has removes the
/// second store, and with it the whole failure.
@MainActor
enum PreviewJourneyStore {
    private static var stored: ModelContext?

    static func context(on container: ModelContainer) -> ModelContext {
        if let stored { return stored }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        stored = context
        return context
    }
}
