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
        NavigationStack(path: $navigationPath) {
            if today_trains.isEmpty {
                ContentUnavailableView("No ongoing journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the button below."))
                .padding()
                .foregroundColor(Color.primary)
                .fontDesign(app_font_design)
            } else {
                let stopsByTrain = Dictionary(grouping: stops, by: { $0.id })
                let seatsByTrain = Dictionary(grouping: seats, by: { $0.trainID })
                
                List {
                    ForEach(Array(today_trains.enumerated()), id: \.element.id) { index, train in
                        // compute stops and summary for this train
                        let trainStops = (stopsByTrain[train.id] ?? [])
                            .sorted(by: { $0.ref_time < $1.ref_time })
                        
                        let summary = StopSummary.calculate(for: train.id, in: trainStops)
                        
                        let trainSeats = (seatsByTrain[train.id] ?? [])
                            .sorted {
                                if $0.carriage != $1.carriage {
                                    return $0.carriage < $1.carriage
                                } else if $0.number != $1.number {
                                    return $0.number < $1.number
                                } else {
                                    return $0.name < $1.name
                                }
                            }
                        
                        let nextTrain = index + 1 < today_trains.count ? today_trains[index + 1] : nil
                        
                        // determine if there’s an interval before or after this train
                        let hasIntervalBefore = hasInterval(from: index - 1, to: index, stopsByTrain: stopsByTrain)
                        let hasIntervalAfter = hasInterval(from: index, to: index + 1, stopsByTrain: stopsByTrain)
                        
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
                                    
                                    let connectionStatus: (text: String, icon: String, color: Color) = {
                                        if totalMinutes < 10 {
                                            return (String(localized: "Hurry up! High risk"), "figure.run", .red)
                                        } else if totalMinutes < 20 {
                                            return (String(localized: "Tight connection"), "exclamationmark.triangle.fill", .orange)
                                        } else {
                                            return (String(localized: "Time to relax"), "cup.and.saucer.fill", .green)
                                        }
                                    }()
                                    
                                    let timeString = hours > 0
                                    ? "\(hours)h \(minutes)m"
                                    : "\(minutes)m"
                                    
                                    HStack(alignment: .center, spacing: 8) {
                                        Rectangle()
                                            .fill(connectionStatus.color.opacity(0.3))
                                            .frame(width: 3, height: 20)
                                            .cornerRadius(1.5)
                                        
                                        Image(systemName: connectionStatus.icon)
                                            .font(.footnote)
                                        
                                        Text("\(NSLocalizedString("Connection:", comment: "")) \(timeString)")
                                            .font(.caption).fontWeight(.semibold)
                                            .contentTransition(.numericText(value: Double(totalMinutes)))
                                            .animation(.snappy, value: totalMinutes)
                                        
                                        Text("•")
                                        
                                        Text(connectionStatus.text)
                                            .font(.caption)
                                            .contentTransition(.numericText(value: Double(totalMinutes)))
                                            .animation(.snappy, value: totalMinutes)
                                        
                                        Spacer()
                                    }
                                    .fontDesign(app_font_design)
                                    .foregroundColor(connectionStatus.color)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(connectionStatus.color.opacity(0.05))
                                    .cornerRadius(16)
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: delete_today_trains)
                }
                .scrollIndicators(.hidden)
                .listStyle(.plain)
                .padding(.horizontal)
                .refreshable {
                    Task { await update_today_trains() }
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
                await update_today_trains()
                
                // Loop every 30 seconds
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    if Task.isCancelled { break }
                    
                    print("🔄 Updating today trains data...\(today_trains.count)/\(trains.count) at \(Date().formatted(date: .abbreviated, time: .standard))")
                    await update_today_trains()
                }
            }
        }
        .onDisappear {
            // Optional: cancel task on disappear if you don't want it running in background
            // updateTask?.cancel()
        }
    }
    
    // MARK: - functions
    private func delete_today_trains(at offsets: IndexSet) {
        let items = offsets.map { today_trains[$0] }
        for train in items {
            let relatedStops = stops.filter { $0.id == train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(train)
        }
    }
    
    private func update_today_trains() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        
        let trainsToUpdate = today_trains
        
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
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func hasInterval(from sourceIndex: Int, to targetIndex: Int, stopsByTrain: [UUID: [Stop]]) -> Bool {
        // Validate indices
        guard sourceIndex >= 0, sourceIndex < today_trains.count,
              targetIndex >= 0, targetIndex < today_trains.count else {
            return false
        }
        
        // Get source and target trains
        let sourceTrain = today_trains[sourceIndex]
        let targetTrain = today_trains[targetIndex]
        
        // Get relevant stops for both trains using pre-grouped data
        let sourceStops = (stopsByTrain[sourceTrain.id] ?? []).filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        let targetStops = (stopsByTrain[targetTrain.id] ?? []).filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        
        // check the name and time conditions
        guard let sourceLastStop = sourceStops.last, let targetFirstStop = targetStops.first else { return false }
        return (sourceLastStop.name == targetFirstStop.name) && (sourceLastStop.arr_time_eff < targetFirstStop.dep_time_eff)
    }
}
