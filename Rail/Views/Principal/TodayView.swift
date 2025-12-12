import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    @State private var add_journey_sheet = false
    
    private var today_trains: [Train] {
        trains
            .compactMap { train in
                let trainStops = stops
                    .filter { $0.id == train.id }
                    .sorted(by: { $0.ref_time < $1.ref_time })
                
                guard !trainStops.isEmpty else { return nil }
                return train
            }
            .sorted { lhs, rhs in
                guard
                    let lhsFirstStop = stops
                        .filter({ $0.id == lhs.id && $0.is_selected })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first,
                    let rhsFirstStop = stops
                        .filter({ $0.id == rhs.id && $0.is_selected })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first
                else { return false }
                
                return lhsFirstStop.dep_time_eff < rhsFirstStop.dep_time_eff
            }
            .filter { train in
                let trainStops = stops
                    .filter { $0.id == train.id }
                    .sorted(by: { $0.ref_time < $1.ref_time })
                
                guard let lastStop = trainStops.last else { return false }
                return Date() <= lastStop.arr_time_eff || Calendar.current.isDateInToday(lastStop.arr_time_eff)
            }
    }
    
    var body: some View {
        NavigationStack {
            if today_trains.isEmpty {
                ContentUnavailableView("No ongoing journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the above button."))
                .padding()
                .foregroundColor(Color.primary)
                .fontDesign(appFontDesign)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            add_journey_sheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            } else {
                List {
                    ForEach(Array(today_trains.enumerated()), id: \.element.id) { index, train in
                        // compute stops for this train
                        let trainStops = stopsByTrain[train.id] ?? []
                        
                        // safely find previous and next trains
                        let previousTrain = index > 0 ? today_trains[index - 1] : nil
                        let nextTrain = index + 1 < today_trains.count ? today_trains[index + 1] : nil
                        
                        // determine if there’s an interval before or after this train
                        let hasIntervalBefore = previousTrain.flatMap { intervalBetween($0, train, stops: stops) } != nil
                        let hasIntervalAfter = nextTrain.flatMap { intervalBetween(train, $0, stops: stops) } != nil
                        
                        // adjust vertical padding based on intervals
                        let topPadding: CGFloat = hasIntervalBefore ? 2 : (index == 0 ? 16 : 24)
                        let bottomPadding: CGFloat = hasIntervalAfter ? 2 : 24
                        
                        VStack(spacing: 0) {
                            // MARK: - train row
                            ZStack {
                                ListView(train: train, stops: trainStops)
                                    .padding(.top, topPadding)
                                    .padding(.bottom, bottomPadding)

                                NavigationLink(destination: DetailsView(train: train, stops: trainStops)) {
                                    EmptyView()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .opacity(0)
                            }
                            
                            // MARK: - interval row
                            if hasIntervalAfter,
                               let nextTrain,
                               let interval = intervalBetween(train, nextTrain, stops: stops) {
                                
                                let hours = Int(interval) / 3600
                                let minutes = (Int(interval) % 3600) / 60
                                let timeString = hours > 0
                                    ? "\(NSLocalizedString("Waiting for", comment: "")) \(hours)h \(minutes)m"
                                    : "\(NSLocalizedString("Waiting for", comment: "")) \(minutes)m"
                                
                                Text(timeString)
                                    .font(.footnote)
                                    .fontDesign(appFontDesign)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
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
                    update_today_trains()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            add_journey_sheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .sheet(isPresented: $add_journey_sheet) {
            AddJourneyView()
        }
        .onAppear {
            print("Actual iPhone language: \(Locale.current)")
            update_today_trains()
            
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                update_today_trains()
            }
        }
    }
    
    // MARK: - Data functions
    private func delete_today_trains(at offsets: IndexSet) {
        let items = offsets.map { today_trains[$0] }
        for train in items {
            let relatedStops = stops.filter { $0.id == train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(train)
        }
    }
    
    private func update_today_trains() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for train in today_trains {
                    group.addTask {
                        await update_train(train)
                    }
                }
            }
            print("🔄 \(today_trains.count) trains updated at \(Date().formatted(date: .abbreviated, time: .standard))")
        }
    }
    
    func update_train(_ train: Train) async {
        let result: [String: Any]
        
        if train.provider == "trenitalia" {
            result = await fetch_trenitalia_train_info_async(identifier: train.identifier)
        } else {
            result = await fetch_italo_train_info_async(identifier: train.identifier)
        }
        
        await MainActor.run {
            apply_result(result, to: train)
        }
    }
    
    func fetch_trenitalia_train_info_async(identifier: String) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            fetch_trenitalia_train_info(identifier: identifier) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    func fetch_italo_train_info_async(identifier: String) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            fetch_italo_train_info(identifier: identifier) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    @MainActor
    private func apply_result(_ result: [String: Any], to train: Train) {
        train.last_upadate_time = result["last_update_time"] as? Date ?? .distantPast
        train.delay = result["delay"] as? Int ?? 0
        train.direction = result["direction"] as? String ?? ""
        train.issue = result["issue"] as? String ?? ""

        if let fetchedStops = result["stops"] as? [[String: Any]] {
            let currentStops = stops.filter { $0.id == train.id }

            for stop in currentStops {
                guard let fetched = fetchedStops.first(where: { ($0["name"] as? String) == stop.name }) else { continue }
                
                stop.platform = fetched["platform"] as? String ?? ""
                stop.weather = fetched["weather"] as? String ?? ""
                stop.status = fetched["status"] as? Int ?? 0
                stop.is_completed = fetched["is_completed"] as? Bool ?? false
                stop.is_in_station = fetched["is_in_station"] as? Bool ?? false
                stop.dep_delay = fetched["dep_delay"] as? Int ?? 0
                stop.arr_delay = fetched["arr_delay"] as? Int ?? 0
                stop.dep_time_eff = fetched["dep_time_eff"] as? Date ?? .distantPast
                stop.arr_time_eff = fetched["arr_time_eff"] as? Date ?? .distantPast
            }
        }
        
        // --- ADD THIS BLOCK ---
            // 1. Determine if this train is currently the "active" one
            let isTraveling = checkIfTraveling(train) // You'll need a simple logic for this
            
            if isTraveling {
                // 2. Find the next stop (simplified logic)
                let nextStopName = stops.first(where: { $0.id == train.id && !$0.is_completed })?.name ?? "End"
                
                // 3. Send to Watch
                ConnectivityManager.shared.sendTrainUpdate(
                    isTraveling: true,
                    trainNumber: train.number,
                    delay: train.delay,
                    nextStop: nextStopName
                )
            }
            // ----------------------

        do {
            try modelContext.save()
        } catch {
            print("⚠️ Failed to save modelContext after applying result for train \(train.identifier):", error)
        }
    }
    
    // Helper function to define "Traveling"
    private func checkIfTraveling(_ train: Train) -> Bool {
        // Example logic: active if it started but hasn't finished
        // You can refine this based on your exact 'stops' data
        return true // Placeholder: Implement your specific time check here
    }
    
    // MARK: - Performance functions
    private func intervalBetween(_ train: Train, _ nextTrain: Train, stops: [Stop]) -> TimeInterval? {
        let trainStops = stopsByTrain[train.id] ?? []
        let nextTrainStops = stops.filter { $0.id == nextTrain.id }.sorted { $0.ref_time < $1.ref_time }
        
        guard let last = trainStops.last,
              let first = nextTrainStops.first,
              last.name == first.name else { return nil }
        
        let interval = {
            if Calendar.current.isDateInToday(first.ref_time) {
                return first.dep_time_eff.timeIntervalSince(last.arr_time_eff)
            } else {
                return first.ref_time.timeIntervalSince(last.arr_time_id)
            }
        }()
        
        return (interval > 0 && interval <= 24 * 60 * 60) ? interval : nil
    }
    
    private var stopsByTrain: [UUID: [Stop]] {
        Dictionary(grouping: stops, by: { $0.id })
            .mapValues { $0.sorted(by: { $0.ref_time < $1.ref_time }) }
    }
}
