import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct TodayView: View {
    // MARK: - Properties

    @Environment(\.requestReview) var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @Binding var ticketTrainID: UUID?
    @Binding var ticketSeatID: UUID?
    @Binding var showTicketView: Bool
    @Binding var searchText: String
    @Binding var navigationPath: [Train]
    var isActive: Bool = true

    /// A clock for previews and screenshots. The mock journeys are staged around a
    /// particular moment, and the list only tells that story if it agrees.
    var previewNow: Date? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    @Query private var profiles: [UserProfile]
    @Query private var passes: [Pass]

    @State private var isUpdating = false
    @State private var manualRefreshCounter = 0
    @State private var rowItems: [TrainRowItem] = []
    @State private var listNow = Date()
    @State private var stopsByTrain: [UUID: [Stop]] = [:]
    @State private var refreshTask: Task<Void, Never>?
    /// Journeys broken out into their trains; every other one stays folded.
    @State private var expandedJourneys: Set<UUID> = []

    private static let minUpdateInterval: TimeInterval = 25

    // MARK: - Computed

    private var filteredRowItems: [TrainRowItem] {
        rowItems.filter { TrainListBuilder.matches($0, searchText: searchText) }
    }

    /// What the list draws: a train on its own, a journey folded into one row, or a
    /// broken-out journey's trains one after the other.
    private var rowEntries: [TodayRowEntry] {
        TrainListBuilder.journeys(in: filteredRowItems).flatMap { legs -> [TodayRowEntry] in
            guard legs.count > 1, let journeyID = legs.first?.train.journeyID else {
                return legs.map { TodayRowEntry(item: $0, trains: [$0]) }
            }
            guard !expandedJourneys.contains(journeyID) else {
                return legs.enumerated().map { index, leg in
                    TodayRowEntry(item: leg, trains: [leg], journeyID: index == 0 ? journeyID : nil, isExpanded: true)
                }
            }
            return [TodayRowEntry(
                item: TrainListBuilder.collapsed(legs, now: listNow),
                trains: legs,
                journeyID: journeyID,
                headerTrain: legs[0].train,
                extraCount: legs.count - 1
            )]
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if filteredRowItems.isEmpty {
                if rowItems.isEmpty {
                    ContentUnavailableView {
                        Label("No ongoing journeys", systemImage: "exclamationmark.magnifyingglass")
                    } description: {
                        Text("Add a new journey by tapping the button below.")
                    }
                    .padding()
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                } else {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("No trains match \"\(searchText)\".")
                    )
                    .padding()
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                }
            } else {
                let entries = rowEntries
                List {
                    ForEach(entries) { entry in
                        TodayTrainRow(
                            item: entry.item,
                            now: listNow,
                            manualRefreshCounter: manualRefreshCounter,
                            isFirst: entry.id == entries.first?.id,
                            isLast: entry.id == entries.last?.id,
                            headerTrain: entry.headerTrain,
                            extraCount: entry.extraCount,
                            isExpanded: entry.isExpanded,
                            onToggleExpanded: entry.journeyID.map { id in { toggleJourney(id) } }
                        )
                        .equatable()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteTodayTrains)
                }
                .scrollIndicators(.hidden)
                .listStyle(.insetGrouped)
                .refreshable {
                    refreshRowItems()
                    await updateTodayTrains(isManual: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            if rowItems.isEmpty {
                refreshRowItems()
            }
        }
        .onChange(of: ticketTrainID) { _, newID in
            // Outside the list on purpose: attached to it, a journey arriving while
            // the list was still empty — the first one added from a board — had
            // nothing listening, and the push was dropped.
            guard let id = newID, let train = trains.first(where: { $0.id == id }) else { return }
            if navigationPath.last?.id != train.id {
                navigationPath.append(train)
            }
            ticketTrainID = nil
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the front is the only chance the Live Activities get to
            // move on: the next stop, the countdown's target and the middle row are
            // all recomputed here, and a journey that ended while the app was away
            // is taken down. It also picks up anything that drifted while Rail was
            // not running, which with no server is the whole story.
            guard phase == .active else { return }
            refreshRowItems()
            syncJourneyState()
        }
        .onChange(of: trains.count) { _, _ in
            scheduleRefreshRowItems()
            syncJourneyState()
        }
        .onChange(of: stops.count) { _, _ in scheduleRefreshRowItems() }
        .onChange(of: passes.count) { _, _ in syncJourneyState() }
        // A passenger's seat is drawn on the Lock Screen, so adding one, removing one
        // and correcting one all have to reach it. The count alone missed the last.
        .onChange(of: seatSignature) { _, _ in syncJourneyState() }
        .onChange(of: profiles.primary?.notificationSettings) { _, _ in syncJourneyState() }
        .task(id: isActive) {
            guard isActive else { return }
            refreshRowItems()
            await updateTodayTrains()
            syncJourneyState()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await updateTodayTrains()
                // A leg finishing is what hands the Lock Screen to whichever train
                // is next, and that only happens here: nothing else touches the
                // Live Activities while the app just sits open on this list.
                syncJourneyState()
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                listNow = previewNow ?? Date()
            }
        }
    }

    // MARK: - Actions

    private func toggleJourney(_ id: UUID) {
        HapticFeedback.select()
        withAnimation(.smooth) {
            if expandedJourneys.remove(id) == nil { expandedJourneys.insert(id) }
        }
    }

    private func scheduleRefreshRowItems() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            refreshRowItems()
        }
    }

    /// What the Lock Screen shows of the seats, cheap to compare. The QR images are
    /// left out on purpose: reading them would load every one on each pass.
    private var seatSignature: [String] {
        seats.map { "\($0.id)|\($0.trainID)|\($0.carriage)|\($0.number)" }
    }

    /// Rebuilds everything the journeys have promised elsewhere on the device: the
    /// pending alerts, and the Live Activities on the Lock Screen. Both are rebuilt
    /// from the times now in the store, so a delay picked up by a refresh drags them
    /// both along with it.
    ///
    /// They go together on purpose. The alert is the fallback for a device where
    /// Live Activities are off or were refused, so the two must never be scheduled
    /// from different readings of the same journey.
    ///
    /// Alerts are local to a device, so this also runs when iCloud brings the
    /// preferences over from another one — including a switch turned off there,
    /// which clears them here.
    private func syncJourneyState() {
        let currentTrains = trains
        let currentStops = stops
        let currentPasses = passes
        let currentSeats = seats
        let settings = profiles.primary?.resolvedNotificationSettings

        Task {
            if let settings {
                await NotificationManager.shared.syncAlerts(
                    trains: currentTrains,
                    stops: currentStops,
                    passes: currentPasses,
                    settings: settings
                )
            }

            await TrainActivityManager.shared.sync(
                trains: currentTrains,
                stops: currentStops,
                seats: currentSeats
            )
        }
    }

    private func refreshRowItems() {
        listNow = previewNow ?? Date()
        stopsByTrain = Dictionary(grouping: stops, by: \.id)
        rowItems = TrainListBuilder.todayItems(trains: trains, stops: stops, now: listNow)
    }

    private func deleteTodayTrains(at offsets: IndexSet) {
        // a folded journey goes as a whole, every train in it
        let entries = rowEntries
        let items = offsets.flatMap { entries[$0].trains }
        for item in items {
            let trainID = item.train.id
            Task {
                await CalendarManager.shared.removeTrainEvent(train: item.train)
            }
            // Ended by id rather than left to the rebuild below: by then the train
            // is out of the store and there is nothing left to match it against.
            Task { await TrainActivityManager.shared.end(tripID: trainID) }

            let relatedStops = stops.filter { $0.id == item.train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(item.train)
        }
        refreshRowItems()
    }

    @MainActor
    private func updateTodayTrains(isManual: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let trainsToUpdate = rowItems.map(\.train)
        let currentStopsByTrain = stopsByTrain
        let calendarSettings = profiles.primary?.calendarSettings
        let allSeats = seats

        // Move the journey on from the times already stored before asking the
        // network for anything: with no connection this is the only thing that
        // keeps the list live, and a successful refresh overwrites it below.
        var didChange = trainsToUpdate.reduce(false) { changed, train in
            TrainProgress.advance(train: train, stops: currentStopsByTrain[train.id] ?? [])
                || changed
        }
        await withTaskGroup(of: Bool.self) { group in
            for train in trainsToUpdate {
                let trainStops = currentStopsByTrain[train.id] ?? []
                let firstStop_refTime = trainStops.min(by: { $0.ref_time < $1.ref_time })?.ref_time ?? .distantPast
                guard Calendar.current.isDateInToday(firstStop_refTime) else { continue }

                if !isManual, Date().timeIntervalSince(train.last_update_time) < Self.minUpdateInterval {
                    continue
                }

                group.addTask {
                    let results: [String: Any] = await {
                        switch train.provider {
                        case "trenitalia":
                            return await TrenitaliaAPI().info(identifier: train.identifier, shouldFetchWeather: false) ?? [:]
                        case "italo":
                            return await ItaloAPI().info(identifier: train.identifier, shouldFetchWeather: false) ?? [:]
                        default:
                            return [:]
                        }
                    }()

                    return await MainActor.run {
                        guard !results.isEmpty else { return false }

                        // only write values that actually changed so unchanged refreshes
                        // don't dirty the context and re-render observers
                        var trainChanged = false
                        let newDelay = results["delay"] as? Int ?? 0
                        let newDirection = results["direction"] as? String ?? ""
                        let newIssue = results["issue"] as? String ?? ""

                        if train.delay != newDelay { train.delay = newDelay; trainChanged = true }
                        if train.direction != newDirection { train.direction = newDirection; trainChanged = true }
                        if train.issue != newIssue { train.issue = newIssue; trainChanged = true }

                        let todayStops = currentStopsByTrain[train.id] ?? []
                        let stopsUpdated = results["stops"] as? [[String: Any]] ?? []

                        for stop in todayStops {
                            guard let stopUpdated = stopsUpdated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }

                            let newPlatform = stopUpdated["platform"] as? String ?? ""
                            let newWeather = stopUpdated["weather"] as? String ?? ""
                            let newStatus = stopUpdated["status"] as? Int ?? 0
                            let newCompleted = stopUpdated["is_completed"] as? Bool ?? false
                            let newInStation = stopUpdated["is_in_station"] as? Bool ?? false
                            let newDepDelay = stopUpdated["dep_delay"] as? Int ?? 0
                            let newArrDelay = stopUpdated["arr_delay"] as? Int ?? 0
                            let newDepEff = stopUpdated["dep_time_eff"] as? Date ?? .distantPast
                            let newArrEff = stopUpdated["arr_time_eff"] as? Date ?? .distantPast

                            if stop.platform != newPlatform { stop.platform = newPlatform; trainChanged = true }
                            if !newWeather.isEmpty && stop.weather != newWeather { stop.weather = newWeather; trainChanged = true }
                            if stop.status != newStatus { stop.status = newStatus; trainChanged = true }
                            if stop.is_completed != newCompleted { stop.is_completed = newCompleted; trainChanged = true }
                            if stop.is_in_station != newInStation { stop.is_in_station = newInStation; trainChanged = true }
                            if stop.dep_delay != newDepDelay { stop.dep_delay = newDepDelay; trainChanged = true }
                            if stop.arr_delay != newArrDelay { stop.arr_delay = newArrDelay; trainChanged = true }
                            if stop.dep_time_eff != newDepEff { stop.dep_time_eff = newDepEff; trainChanged = true }
                            if stop.arr_time_eff != newArrEff { stop.arr_time_eff = newArrEff; trainChanged = true }
                        }

                        if trainChanged {
                            train.last_update_time = results["last_update_time"] as? Date ?? .distantPast
                        }

                        if train.calendarEventIdentifier != nil, let settings = calendarSettings {
                            Task {
                                let trainSeats = allSeats.filter { $0.trainID == train.id }
                                await CalendarManager.shared.syncTrainEvent(
                                    train: train,
                                    stops: todayStops,
                                    seats: trainSeats,
                                    titleFormat: settings.titleFormat,
                                    calendarIdentifier: settings.calendarIdentifier,
                                    travelTime: settings.travelTime
                                )
                            }
                        }

                        return trainChanged
                    }
                }
            }

            for await changed in group {
                if changed { didChange = true }
            }
        }

        if didChange {
            try? modelContext.save()
            refreshRowItems()
            syncJourneyState()
        }

        if isManual {
            manualRefreshCounter += 1
            reloadWidgetTimelines()
        }
    }
}

/// One row of the Today list.
private struct TodayRowEntry: Identifiable {
    /// What the row draws.
    let item: TrainRowItem
    /// What deleting the row takes with it: every train in a folded journey.
    let trains: [TrainRowItem]
    /// Set on a journey's lead row, folded or not, which carries the chevron.
    var journeyID: UUID? = nil
    var headerTrain: Train? = nil
    var extraCount: Int = 0
    var isExpanded: Bool = false

    var id: UUID { item.id }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, configurations: config)
    
    let now = Date()
    let calendar = Calendar.current
    
    // the three are one journey, so the list folds them into a single row
    let journeyID = UUID()

    // Train 1: Roma -> Milano
    let train1ID = UUID()
    let train1 = Train(
        id: train1ID,
        logo: "FR",
        number: "9612",
        identifier: "9612",
        provider: "trenitalia",
        last_update_time: now,
        delay: 5,
        direction: "Milano Centrale",
        issue: "",
        journeyID: journeyID
    )
    
    let train1Stop1 = Stop(
        id: train1ID,
        name: "Roma Termini",
        platform: "10",
        weather: "☀️",
        is_selected: true,
        status: 0,
        is_completed: true,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: calendar.date(byAdding: .hour, value: -3, to: now)!,
        arr_time_id: calendar.date(byAdding: .hour, value: -3, to: now)!,
        dep_time_eff: calendar.date(byAdding: .hour, value: -3, to: now)!,
        arr_time_eff: calendar.date(byAdding: .hour, value: -3, to: now)!,
        ref_time: calendar.date(byAdding: .hour, value: -3, to: now)!
    )
    
    let train1Stop2 = Stop(
        id: train1ID,
        name: "Milano Centrale",
        platform: "3",
        weather: "☁️",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: true,
        dep_delay: 0,
        arr_delay: 5,
        dep_time_id: calendar.date(byAdding: .minute, value: -5, to: now)!,
        arr_time_id: calendar.date(byAdding: .minute, value: -5, to: now)!,
        dep_time_eff: calendar.date(byAdding: .minute, value: -5, to: now)!,
        arr_time_eff: calendar.date(byAdding: .minute, value: -5, to: now)!,
        ref_time: calendar.date(byAdding: .minute, value: -5, to: now)!
    )
    
    // Train 2: Milano -> Torino (Tight Connection: 15 min)
    let train2ID = UUID()
    let train2 = Train(
        id: train2ID,
        logo: "FR",
        number: "9544",
        identifier: "9544",
        provider: "trenitalia",
        last_update_time: now,
        delay: 0,
        direction: "Torino Porta Nuova",
        issue: "",
        journeyID: journeyID
    )
    
    let train2Stop1 = Stop(
        id: train2ID,
        name: "Milano Centrale",
        platform: "5",
        weather: "☁️",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: calendar.date(byAdding: .minute, value: 10, to: now)!,
        arr_time_id: calendar.date(byAdding: .minute, value: 10, to: now)!,
        dep_time_eff: calendar.date(byAdding: .minute, value: 10, to: now)!,
        arr_time_eff: calendar.date(byAdding: .minute, value: 10, to: now)!,
        ref_time: calendar.date(byAdding: .minute, value: 10, to: now)!
    )
    
    let train2Stop2 = Stop(
        id: train2ID,
        name: "Torino Porta Nuova",
        platform: "1",
        weather: "🌧️",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: calendar.date(byAdding: .hour, value: 1, to: now)!,
        arr_time_id: calendar.date(byAdding: .hour, value: 1, to: now)!,
        dep_time_eff: calendar.date(byAdding: .hour, value: 1, to: now)!,
        arr_time_eff: calendar.date(byAdding: .hour, value: 1, to: now)!,
        ref_time: calendar.date(byAdding: .hour, value: 1, to: now)!
    )
    
    // Train 3: Torino -> Paris (Relaxed Connection: 75 min)
    let train3ID = UUID()
    let train3 = Train(
        id: train3ID,
        logo: "FR",
        number: "9248",
        identifier: "9248",
        provider: "trenitalia",
        last_update_time: now,
        delay: 0,
        direction: "Paris Gare de Lyon",
        issue: "",
        journeyID: journeyID
    )
    
    let train3Stop1 = Stop(
        id: train3ID,
        name: "Torino Porta Nuova",
        platform: "3",
        weather: "🌧️",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: calendar.date(byAdding: .minute, value: 135, to: now)!,
        arr_time_id: calendar.date(byAdding: .minute, value: 135, to: now)!,
        dep_time_eff: calendar.date(byAdding: .minute, value: 135, to: now)!,
        arr_time_eff: calendar.date(byAdding: .minute, value: 135, to: now)!,
        ref_time: calendar.date(byAdding: .minute, value: 135, to: now)!
    )
    
    let train3Stop2 = Stop(
        id: train3ID,
        name: "Paris Gare de Lyon",
        platform: "A",
        weather: "🌤️",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: calendar.date(byAdding: .hour, value: 6, to: now)!,
        arr_time_id: calendar.date(byAdding: .hour, value: 6, to: now)!,
        dep_time_eff: calendar.date(byAdding: .hour, value: 6, to: now)!,
        arr_time_eff: calendar.date(byAdding: .hour, value: 6, to: now)!,
        ref_time: calendar.date(byAdding: .hour, value: 6, to: now)!
    )
    
    container.mainContext.insert(train1)
    container.mainContext.insert(train1Stop1)
    container.mainContext.insert(train1Stop2)
    
    container.mainContext.insert(train2)
    container.mainContext.insert(train2Stop1)
    container.mainContext.insert(train2Stop2)
    
    container.mainContext.insert(train3)
    container.mainContext.insert(train3Stop1)
    container.mainContext.insert(train3Stop2)
    
    return TodayView(
        ticketTrainID: .constant(nil),
        ticketSeatID: .constant(nil),
        showTicketView: .constant(false),
        searchText: .constant(""),
        navigationPath: .constant([])
    )
        .modelContainer(container)
}
