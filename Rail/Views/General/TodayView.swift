import SwiftUI
import SwiftData
import WidgetKit

struct TodayView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    
    // deep link variables
    @Binding var ticketTrainID: UUID?
    @Binding var show_ticket_view: Bool
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    // sheet variables
    @State private var add_journey_sheet = false
    @State private var isUpdating = false
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var navigationPath: [Train] = []
    
    @State private var updateCounter = 0
    @State private var manualRefreshCounter = 0
    
    // computed variables
    private var today_trains: [Train] {
        let now = Date()
        let calendar = Calendar.current
        
        // Group stops by train ID once to avoid O(N*M) filtering in each iteration
        let stopsByTrain = Dictionary(grouping: stops, by: { $0.id })
        
        return trains
            .filter { train in
                guard let trainStops = stopsByTrain[train.id] else { return false }
                let selectedStops = trainStops.filter { $0.is_selected }
                guard let lastStop = selectedStops.max(by: { $0.ref_time < $1.ref_time }) else { return false }
                return now <= lastStop.arr_time_eff || calendar.isDateInToday(lastStop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                let lhsStops = stopsByTrain[lhs.id] ?? []
                let rhsStops = stopsByTrain[rhs.id] ?? []
                
                let lhsFirst = lhsStops.filter { $0.is_selected }.min(by: { $0.ref_time < $1.ref_time })
                let rhsFirst = rhsStops.filter { $0.is_selected }.min(by: { $0.ref_time < $1.ref_time })
                
                guard let lTime = lhsFirst?.dep_time_eff, let rTime = rhsFirst?.dep_time_eff else { return false }
                return lTime < rTime
            }
    }
    
    // MARK: - main view
    var body: some View {
        let current_today_trains = today_trains
        let stopsByTrain = Dictionary(grouping: stops, by: { $0.id })
        
        NavigationStack(path: $navigationPath) {
            if current_today_trains.isEmpty {
                ContentUnavailableView("No ongoing journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the button below."))
                .padding()
                .foregroundColor(Color.primary)
                .fontDesign(app_font_design)
            } else {
                let seatsByTrain = Dictionary(grouping: seats, by: { $0.trainID })
                
                let totalConnections = current_today_trains.indices.dropLast().reduce(0) { count, i in
                    hasInterval(trains: current_today_trains, from: i, to: i + 1, stopsByTrain: stopsByTrain) ? count + 1 : count
                }
                
                List {
                    ForEach(Array(current_today_trains.enumerated()), id: \.element.id) { index, train in
                        // compute stops and summary for this train
                        let trainStops = (stopsByTrain[train.id] ?? [])
                            .sorted(by: { $0.ref_time < $1.ref_time })
                        
                        let summary = StopSummary.calculate(for: train.id, in: trainStops)
                        
                        let nextTrain = index + 1 < current_today_trains.count ? current_today_trains[index + 1] : nil
                        
                        // determine if there’s an interval before or after this train
                        let hasIntervalBefore = hasInterval(trains: current_today_trains, from: index - 1, to: index, stopsByTrain: stopsByTrain)
                        let hasIntervalAfter = hasInterval(trains: current_today_trains, from: index, to: index + 1, stopsByTrain: stopsByTrain)
                        
                        // adjust vertical padding based on intervals
                        let topPadding: CGFloat = hasIntervalBefore ? 2 : (index == 0 ? 16 : 24)
                        let bottomPadding: CGFloat = hasIntervalAfter ? 2 : 24
                        
                        VStack(spacing: 0) {
                            // MARK: - train row
                            ZStack {
                                ListView(train: train, stops: trainStops, summary: summary)
                                    .padding(.top, topPadding)
                                    .padding(.bottom, bottomPadding)
                                
                                NavigationLink(value: train) {
                                    EmptyView()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .opacity(0)
                            }
                            
                            // MARK: - interval row
                            if hasIntervalAfter, let nextTrain {
                                let currentArrDate = summary.last.arr_time_eff
                                
                                let nextTrainStops = (stopsByTrain[nextTrain.id] ?? []).filter { $0.is_selected }
                                let nextDepDate = nextTrainStops.min(by: { $0.ref_time < $1.ref_time })?.dep_time_eff ?? .distantPast
                                
                                let interval = nextDepDate.timeIntervalSince(currentArrDate)
                                
                                if interval > 0 && interval <= 24 * 60 * 60 {
                                    let totalMinutes = Int(interval) / 60
                                    let hours = totalMinutes / 60
                                    let minutes = totalMinutes % 60
                                    
                                    let durationString = hours > 0
                                    ? "\(hours)h \(minutes)m"
                                    : "\(minutes)m"
                                    
                                    let connectionStatus = ConnectionStatus(minutes: totalMinutes)
                                    
                                    let currentConnectionIndex = current_today_trains.indices.prefix(index + 1).reduce(0) { count, i in
                                        hasInterval(trains: current_today_trains, from: i, to: i + 1, stopsByTrain: stopsByTrain) ? count + 1 : count
                                    }
                                    
                                    ConnectionIntervalView(
                                        durationString: durationString,
                                        totalMinutes: totalMinutes,
                                        connectionStatus: connectionStatus,
                                        station: summary.last.name,
                                        weather: summary.last.weather,
                                        index: currentConnectionIndex,
                                        total: totalConnections,
                                        manualRefreshCounter: manualRefreshCounter
                                    )
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: { offsets in
                        delete_today_trains(at: offsets, current_today_trains: current_today_trains)
                    })
                }
                .scrollIndicators(.hidden)
                .listStyle(.plain)
                .padding(.horizontal)
                .refreshable {
                    Task { await update_today_trains(current_today_trains: current_today_trains, isManual: true) }
                }
                .navigationDestination(for: Train.self) { train in
                    let trainStops = stops.filter { $0.id == train.id }.sorted(by: { $0.ref_time < $1.ref_time })
                    let trainSeats = seats.filter { $0.trainID == train.id }
                    DetailsView(train: train, stops: trainStops, seats: trainSeats, show_ticket_initially: $show_ticket_view)
                }
                .onChange(of: ticketTrainID) { _, newID in
                    if let id = newID, let train = trains.first(where: { $0.id == id }) {
                        // Only push if not already at the top of the stack
                        if navigationPath.last?.id != train.id {
                            navigationPath.append(train)
                        }
                        ticketTrainID = nil
                    }
                }
            }
        }
        .sheet(isPresented: $add_journey_sheet) {
            AddTrainView(add_favorite_sheet: false)
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            
            print("Actual iPhone language: \(Locale.current)")
            
            // Cancel existing task if any to prevent duplicates
            updateTask?.cancel()
            
            updateTask = Task {
                print("🔄 Starting update loop at \(Date().formatted(date: .abbreviated, time: .standard))")
                // Initial update
                await update_today_trains(current_today_trains: current_today_trains)
                
                // Loop every 30 seconds
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    if Task.isCancelled { break }
                    
                    print("🔄 Updating today trains data...\(current_today_trains.count)/\(trains.count) at \(Date().formatted(date: .abbreviated, time: .standard))")
                    await update_today_trains(current_today_trains: current_today_trains)
                }
            }
        }
        .onDisappear {
            // Optional: cancel task on disappear if you don't want it running in background
            // updateTask?.cancel()
        }
    }
    
    // MARK: - functions
    private func delete_today_trains(at offsets: IndexSet, current_today_trains: [Train]) {
        let items = offsets.map { current_today_trains[$0] }
        for train in items {
            let relatedStops = stops.filter { $0.id == train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(train)
        }
    }
    
    private func update_today_trains(current_today_trains: [Train], isManual: Bool = false) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        
        let trainsToUpdate = current_today_trains
        
        await withTaskGroup(of: Void.self) { group in
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
                    // fetch new data
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
                    
                    await MainActor.run {
                        // update train data
                        train.last_update_time = results["last_update_time"] as? Date ?? .distantPast
                        train.delay = results["delay"] as? Int ?? 0
                        train.direction = results["direction"] as? String ?? ""
                        train.issue = results["issue"] as? String ?? ""
                        
                        // update stops data
                        let today_stops = stops.filter { $0.id == train.id }
                        let stops_updated = results["stops"] as? [[String:Any]] ?? []
                        
                        for stop in today_stops {
                            /// get the stop updated whose name correspond to the today stops
                            guard let stop_updated = stops_updated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }
                            
                            /// update only the necessary fields
                            stop.platform = stop_updated["platform"] as? String ?? ""
                            if let newWeather = stop_updated["weather"] as? String, !newWeather.isEmpty {
                                stop.weather = newWeather
                            }
                            stop.status = stop_updated["status"] as? Int ?? 0
                            stop.is_completed = stop_updated["is_completed"] as? Bool ?? false
                            stop.is_in_station = stop_updated["is_in_station"] as? Bool ?? false
                            stop.dep_delay = stop_updated["dep_delay"] as? Int ?? 0
                            stop.arr_delay = stop_updated["arr_delay"] as? Int ?? 0
                            stop.dep_time_eff = stop_updated["dep_time_eff"] as? Date ?? .distantPast
                            stop.arr_time_eff = stop_updated["arr_time_eff"] as? Date ?? .distantPast
                        }
                    }
                }
            }
        }
        try? modelContext.save()
        await MainActor.run {
            if isManual {
                manualRefreshCounter += 1
            }
            updateCounter += 1
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private func hasInterval(trains: [Train], from sourceIndex: Int, to targetIndex: Int, stopsByTrain: [UUID: [Stop]]) -> Bool {
        // Validate indices
        guard sourceIndex >= 0, sourceIndex < trains.count,
              targetIndex >= 0, targetIndex < trains.count else {
            return false
        }
        
        // Get source and target trains
        let sourceTrain = trains[sourceIndex]
        let targetTrain = trains[targetIndex]
        
        // Get relevant stops for both trains using pre-grouped data
        let sourceStops = (stopsByTrain[sourceTrain.id] ?? []).filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        let targetStops = (stopsByTrain[targetTrain.id] ?? []).filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        
        // check the name and time conditions
        guard let sourceLastStop = sourceStops.last, let targetFirstStop = targetStops.first else { return false }
        return (sourceLastStop.name == targetFirstStop.name) && (sourceLastStop.arr_time_eff < targetFirstStop.dep_time_eff)
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
    
    @State private var isVisible: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // connection line
            Rectangle()
                .fill(connectionStatus.color.opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)
                .scaleEffect(y: isVisible ? 1.0 : 0.0, anchor: .top)
                .opacity(isVisible ? 1.0 : 0.0)
                .fixedSize(horizontal: true, vertical: false)
            
            HStack(spacing: 8) {
                Image(systemName: connectionStatus.icon)
                    .font(.title3)
                    .symbolEffect(.bounce, value: isVisible)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(NSLocalizedString("Connection:", comment: "")) \(durationString)")
                        .font(.footnote).fontWeight(.semibold)
                        .contentTransition(.numericText(value: Double(totalMinutes)))
                    
                    Text(connectionStatus.text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(x: isVisible ? 0 : -10)
        }
        .padding(.vertical, 8).padding(.horizontal)
        .fontDesign(app_font_design)
        .foregroundColor(connectionStatus.color)
        .onAppear {
            if !isVisible {
                withAnimation(.snappy) {
                    isVisible = true
                }
            }
        }
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
    
    return TodayView(ticketTrainID: .constant(nil), show_ticket_view: .constant(false))
        .modelContainer(container)
}



