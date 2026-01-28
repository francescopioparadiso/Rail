import SwiftUI
import SwiftData

struct TodayView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    // sheet variables
    @State private var add_journey_sheet = false
    
    // computed variables
    private var today_trains: [Train] {
        trains
            .filter { train in
                let train_stops = stops
                    .filter { $0.id == train.id && $0.is_selected }
                    .sorted(by: { $0.ref_time < $1.ref_time })
                
                guard let last_stop = train_stops.last else { return false }
                return Date() <= last_stop.arr_time_eff || Calendar.current.isDateInToday(last_stop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                guard
                    let lhs_first_stop = stops
                        .filter({ $0.id == lhs.id && $0.is_selected })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first,
                    let rhs_first_stop = stops
                        .filter({ $0.id == rhs.id && $0.is_selected })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first
                else { return false }
                
                return lhs_first_stop.dep_time_eff < rhs_first_stop.dep_time_eff
            }
    }
    
    // MARK: - main view
    var body: some View {
        NavigationStack {
            if today_trains.isEmpty {
                ContentUnavailableView("No ongoing journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the button below."))
                .padding()
                .foregroundColor(Color.primary)
                .fontDesign(app_font_design)
            } else {
                List {
                    ForEach(Array(today_trains.enumerated()), id: \.element.id) { index, train in
                        // compute stops for this train
                        let trainStops = stops
                            .filter { $0.id == train.id }
                            .sorted(by: { $0.ref_time < $1.ref_time })
                        
                        let trainSeats = seats
                            .filter { $0.trainID == train.id }
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
                        let hasIntervalBefore = hasInterval(from: index - 1, to: index)
                        let hasIntervalAfter = hasInterval(from: index, to: index + 1)
                        
                        // adjust vertical padding based on intervals
                        let topPadding: CGFloat = hasIntervalBefore ? 2 : (index == 0 ? 16 : 24)
                        let bottomPadding: CGFloat = hasIntervalAfter ? 2 : 24
                        
                        VStack(spacing: 0) {
                            // MARK: - train row
                            ZStack {
                                ListView(train: train, stops: trainStops)
                                    .padding(.top, topPadding)
                                    .padding(.bottom, bottomPadding)
                                
                                NavigationLink(destination: DetailsView(train: train, stops: trainStops, seats: trainSeats)) {
                                    EmptyView()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .opacity(0)
                            }
                            
                            // MARK: - interval row
                            if hasIntervalAfter, let nextTrain {
                                let currentArrDate = stops
                                    .filter { $0.id == train.id && $0.is_selected }
                                    .sorted(by: { $0.ref_time < $1.ref_time })
                                    .last?.arr_time_eff ?? .distantPast
                                
                                let nextDepDate = stops
                                    .filter { $0.id == nextTrain.id && $0.is_selected }
                                    .sorted(by: { $0.ref_time < $1.ref_time })
                                    .first?.dep_time_eff ?? .distantPast
                                
                                let interval = nextDepDate.timeIntervalSince(currentArrDate)
                                
                                if interval > 0 && interval <= 24 * 60 * 60 {
                                    let hours = Int(interval) / 3600
                                    let minutes = (Int(interval) % 3600) / 60
                                    
                                    let timeString = hours > 0
                                    ? "\(NSLocalizedString("Waiting for", comment: "")) \(hours)h \(minutes)m"
                                    : "\(NSLocalizedString("Waiting for", comment: "")) \(minutes)m"
                                    
                                    Text(timeString)
                                        .font(.footnote)
                                        .fontDesign(app_font_design)
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 4)
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
            }
        }
        .sheet(isPresented: $add_journey_sheet) {
            AddTrainView(add_favorite_sheet: false)
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            
            print("Actual iPhone language: \(Locale.current)")
            
            print("🔄 Updating today trains data...\(today_trains.count)/\(trains.count) at \(Date().formatted(date: .abbreviated, time: .standard))")
            Task { await update_today_trains() }
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                print("🔄 Updating today trains data...\(today_trains.count)/\(trains.count) at \(Date().formatted(date: .abbreviated, time: .standard))")
                Task { await update_today_trains() }
            }
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
        for train in today_trains {
            // condition to update
            /// get the first stop ref time
            let firstStop_refTime = stops
                .filter({ $0.id == train.id })
                .sorted(by: { $0.ref_time < $1.ref_time })
                .first?.ref_time ?? .distantPast
            /// check if the first stop ref time is today
            guard Calendar.current.isDateInToday(firstStop_refTime) else { continue }
            
            
            // fetch new data
            let results: [String:Any] = await {
                switch train.provider {
                    case "trenitalia":
                        return await TrenitaliaAPI().info(identifier: train.identifier, should_fetch_weather: true) ?? [:]
                    case "italo":
                        return await ItaloAPI().info(identifier: train.identifier) ?? [:]
                    default:
                        return [:]
                }
            }()
            
            // update train data
            train.last_update_time = results["last_update_time"] as? Date ?? .distantPast
            train.delay = results["delay"] as? Int ?? 0
            train.direction = results["direction"] as? String ?? ""
            train.issue = results["issue"] as? String ?? ""
            
            // update stops data
            let today_stops = stops.filter { $0.id == train.id }
            for stop in today_stops {
                /// get all the stops updated
                let stops_updated = results["stops"] as? [[String:Any]] ?? []
                
                /// get the stop updated whose name correspond to the today stops
                guard let stop_updated = stops_updated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }
                
                /// update only the necessary fields
                stop.platform = stop_updated["platform"] as? String ?? ""
                stop.weather = stop_updated["weather"] as? String ?? ""
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
    
    private func hasInterval(from sourceIndex: Int, to targetIndex: Int) -> Bool {
        // Validate indices
        guard sourceIndex >= 0, sourceIndex < today_trains.count,
              targetIndex >= 0, targetIndex < today_trains.count else {
            return false
        }
        
        // Get source and target trains
        let sourceTrain = today_trains[sourceIndex]
        let targetTrain = today_trains[targetIndex]
        
        // Get relevant stops for both trains
        let sourceStops = stops.filter { $0.id == sourceTrain.id && $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        let targetStops = stops.filter { $0.id == targetTrain.id && $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
        
        // check the name and time conditions
        guard let sourceLastStop = sourceStops.last, let targetFirstStop = targetStops.first else { return false }
        return (sourceLastStop.name == targetFirstStop.name) && (sourceLastStop.arr_time_eff < targetFirstStop.dep_time_eff)
    }
}
