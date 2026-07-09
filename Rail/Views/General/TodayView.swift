import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct TodayView: View {
    // MARK: - variables
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
    @State private var add_journey_sheet = false
    
    // refresh variables
    @State private var isUpdating = false
    @State private var manualRefreshCounter = 0
    @State private var rowItems: [TrainRowItem] = []
    @State private var listNow = Date()
    @State private var stopsByTrain: [UUID: [Stop]] = [:]

    private var filteredRowItems: [TrainRowItem] {
        rowItems.filter { TrainListBuilder.matches($0, searchText: searchText) }
    }

    // MARK: - main view
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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    List {
                        ForEach(filteredRowItems) { item in
                            todayRow(item: item, now: context.date)
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
                }
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
        .sheet(isPresented: $add_journey_sheet) {
            AddTrainView()
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            refreshRowItems()
        }
        .onChange(of: trains.count) { _, _ in refreshRowItems() }
        .onChange(of: stops.count) { _, _ in refreshRowItems() }
        .onChange(of: navigationPath.count) { _, _ in refreshRowItems() }
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
    }

    @ViewBuilder
    private func todayRow(item: TrainRowItem, now: Date) -> some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)
                    .padding(.top, item.topPadding)
                    .padding(.bottom, item.bottomPadding)

                NavigationLink(value: item.train) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .opacity(0)
            }

            if let connection = item.connection {
                ConnectionIntervalView(
                    durationString: connection.durationString,
                    totalMinutes: connection.totalMinutes,
                    connectionStatus: connection.connectionStatus,
                    station: connection.station,
                    weather: connection.weather,
                    index: connection.index,
                    total: connection.total,
                    manualRefreshCounter: manualRefreshCounter
                )
            }
        }
    }

    private func refreshRowItems() {
        listNow = Date()
        stopsByTrain = Dictionary(grouping: stops, by: \.id)
        rowItems = TrainListBuilder.todayItems(trains: trains, stops: stops, now: listNow)
    }
    
    // MARK: - functions
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

    private func update_today_trains(isManual: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let trainsToUpdate = rowItems.map(\.train)
        var didChange = false
        await withTaskGroup(of: Bool.self) { group in
            for train in trainsToUpdate {
                // condition to update
                /// get the first stop ref time
                let firstStop_refTime = stops
                    .filter({ $0.id == train.id })
                    .sorted(by: { $0.ref_time < $1.ref_time })
                    .first?.ref_time ?? .distantPast
                /// check if the first stop ref time is today
                guard Calendar.current.isDateInToday(firstStop_refTime) else { continue }
                
                group.addTask {
                    let results: [String:Any] = await {
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

                        var trainChanged = false
                        let newDelay = results["delay"] as? Int ?? 0
                        let newDirection = results["direction"] as? String ?? ""
                        let newIssue = results["issue"] as? String ?? ""

                        if train.delay != newDelay || train.direction != newDirection || train.issue != newIssue {
                            trainChanged = true
                        }

                        train.last_update_time = results["last_update_time"] as? Date ?? .distantPast
                        train.delay = newDelay
                        train.direction = newDirection
                        train.issue = newIssue

                        let today_stops = stops.filter { $0.id == train.id }
                        let stops_updated = results["stops"] as? [[String:Any]] ?? []

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

                            if stop.platform != newPlatform
                                || (!newWeather.isEmpty && stop.weather != newWeather)
                                || stop.status != newStatus
                                || stop.is_completed != newCompleted
                                || stop.is_in_station != newInStation
                                || stop.dep_delay != newDepDelay
                                || stop.arr_delay != newArrDelay
                                || stop.dep_time_eff != newDepEff
                                || stop.arr_time_eff != newArrEff {
                                trainChanged = true
                            }

                            stop.platform = newPlatform
                            if !newWeather.isEmpty { stop.weather = newWeather }
                            stop.status = newStatus
                            stop.is_completed = newCompleted
                            stop.is_in_station = newInStation
                            stop.dep_delay = newDepDelay
                            stop.arr_delay = newArrDelay
                            stop.dep_time_eff = newDepEff
                            stop.arr_time_eff = newArrEff
                        }

                        if train.calendarEventIdentifier != nil,
                           let settings = profiles.first?.calendarSettings {
                            Task {
                                let trainSeats = seats.filter { $0.trainID == train.id }
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
            await MainActor.run { refreshRowItems() }
        }

        if isManual {
            await MainActor.run {
                manualRefreshCounter += 1
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

// MARK: - Subviews
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
