import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct TodayView: View {
    // MARK: - Properties
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    
    // deep link variables
    @Binding var ticketTrainID: UUID?
    @Binding var ticketSeatID: UUID?
    @Binding var show_ticket_view: Bool
    @Binding var searchText: String
    @Binding var navigationPath: [Train]
    var isActive: Bool = true
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    @Query private var profiles: [UserProfile]

    // state variables
    // refresh variables
    @State private var isUpdating = false
    @State private var manualRefreshCounter = 0
    @State private var rowItems: [TrainRowItem] = []
    @State private var listNow = Date()
    @State private var stopsByTrain: [UUID: [Stop]] = [:]
    @State private var refreshTask: Task<Void, Never>?

    private static let minUpdateInterval: TimeInterval = 25

    private var filteredRowItems: [TrainRowItem] {
        rowItems.filter { TrainListBuilder.matches($0, searchText: searchText) }
    }

    // MARK: - Body
    var body: some View {
        Group {
            if filteredRowItems.isEmpty {
                if rowItems.isEmpty {
                    ContentUnavailableView("No ongoing journeys",
                                           systemImage: "exclamationmark.magnifyingglass",
                                           description: Text("Add a new journey by tapping the button below."))
                    .padding()
                    .foregroundColor(Color.primary)
                    .fontDesign(app_font_design)
                } else {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("No trains match \"\(searchText)\".")
                    )
                    .padding()
                    .fontDesign(app_font_design)
                }
            } else {
                List {
                    ForEach(filteredRowItems) { item in
                        TodayTrainRow(item: item, now: listNow, manualRefreshCounter: manualRefreshCounter)
                            .equatable()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: delete_today_trains)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .padding(.horizontal)
                .refreshable {
                    refreshRowItems()
                    await update_today_trains(isManual: true)
                }
                .onChange(of: ticketTrainID) { _, newID in
                    if let id = newID, let train = trains.first(where: { $0.id == id }) {
                        if navigationPath.last?.id != train.id {
                            navigationPath.append(train)
                        }
                        ticketTrainID = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app_background_color)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            if rowItems.isEmpty {
                refreshRowItems()
            }
        }
        .onChange(of: trains.count) { _, _ in scheduleRefreshRowItems() }
        .onChange(of: stops.count) { _, _ in scheduleRefreshRowItems() }
        .task(id: isActive) {
            guard isActive else { return }
            refreshRowItems()
            await update_today_trains()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await update_today_trains()
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                listNow = Date()
            }
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

    private func refreshRowItems() {
        listNow = Date()
        stopsByTrain = Dictionary(grouping: stops, by: \.id)
        rowItems = TrainListBuilder.todayItems(trains: trains, stops: stops, now: listNow)
    }
    
    // MARK: - Functions
    private func delete_today_trains(at offsets: IndexSet) {
        let items = offsets.map { filteredRowItems[$0] }
        for item in items {
            Task {
                await CalendarManager.shared.removeTrainEvent(train: item.train)
            }

            let relatedStops = stops.filter { $0.id == item.train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(item.train)
        }
        refreshRowItems()
    }

    @MainActor
    private func update_today_trains(isManual: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let trainsToUpdate = rowItems.map(\.train)
        let currentStopsByTrain = stopsByTrain
        let calendarSettings = profiles.first?.calendarSettings
        let allSeats = seats

        var didChange = false
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
                            return await TrenitaliaAPI().info(identifier: train.identifier, should_fetch_weather: false) ?? [:]
                        case "italo":
                            return await ItaloAPI().info(identifier: train.identifier, should_fetch_weather: false) ?? [:]
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

                        let today_stops = currentStopsByTrain[train.id] ?? []
                        let stops_updated = results["stops"] as? [[String: Any]] ?? []

                        for stop in today_stops {
                            guard let stop_updated = stops_updated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }

                            let newPlatform = stop_updated["platform"] as? String ?? ""
                            let newWeather = stop_updated["weather"] as? String ?? ""
                            let newStatus = stop_updated["status"] as? Int ?? 0
                            let newCompleted = stop_updated["is_completed"] as? Bool ?? false
                            let newInStation = stop_updated["is_in_station"] as? Bool ?? false
                            let newDepDelay = stop_updated["dep_delay"] as? Int ?? 0
                            let newArrDelay = stop_updated["arr_delay"] as? Int ?? 0
                            let newDepEff = stop_updated["dep_time_eff"] as? Date ?? .distantPast
                            let newArrEff = stop_updated["arr_time_eff"] as? Date ?? .distantPast

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
                                    stops: today_stops,
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
        }

        if isManual {
            manualRefreshCounter += 1
            reload_widget_timelines()
        }
    }
}

// MARK: - Secondary Views
struct ConnectionIntervalView: View {
    let durationString: String
    let totalMinutes: Int
    let connectionStatus: ConnectionStatus
    let station: String
    let weather: String?
    let index: Int
    let total: Int
    let manualRefreshCounter: Int
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(connectionStatus.color.opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)
                .fixedSize(horizontal: true, vertical: false)
            
            HStack(spacing: 8) {
                Image(systemName: connectionStatus.icon)
                    .font(.title3)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(NSLocalizedString("Connection:", comment: "")) \(durationString)")
                        .font(.footnote).fontWeight(.semibold)
                    
                    Text(connectionStatus.text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 8).padding(.horizontal)
        .fontDesign(app_font_design)
        .foregroundColor(connectionStatus.color)
    }
}

// MARK: - Previews
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, configurations: config)
    
    let now = Date()
    let calendar = Calendar.current
    
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
        issue: ""
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
        issue: ""
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
        issue: ""
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
        show_ticket_view: .constant(false),
        searchText: .constant(""),
        navigationPath: .constant([])
    )
        .modelContainer(container)
}
