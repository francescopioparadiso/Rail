import SwiftUI
import SwiftData

struct ContentView: View {
    // 1. Fetch data from SwiftData, just like on iOS
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    
    // 2. Replicate the grouping logic to "link" trains and stops
    private var stopsByTrain: [UUID: [Stop]] {
        Dictionary(grouping: stops, by: { $0.id })
            .mapValues { $0.sorted(by: { $0.ref_time < $1.ref_time }) }
    }
    
    // 3. Replicate the filtering logic to show only relevant trains
    private var today_trains: [Train] {
        trains
            .compactMap { train in
                // Find stops for this train using the dictionary
                let trainStops = stopsByTrain[train.id] ?? []
                guard !trainStops.isEmpty else { return nil }
                return train
            }
            .sorted { lhs, rhs in
                // Sort by departure time of the first selected stop
                guard
                    let lhsStops = stopsByTrain[lhs.id],
                    let rhsStops = stopsByTrain[rhs.id],
                    let lhsFirst = lhsStops.first(where: { $0.is_selected }),
                    let rhsFirst = rhsStops.first(where: { $0.is_selected })
                else { return false }
                
                return lhsFirst.dep_time_eff < rhsFirst.dep_time_eff
            }
            .filter { train in
                // Filter out completed trains
                let trainStops = stopsByTrain[train.id] ?? []
                guard let lastStop = trainStops.last else { return false }
                
                // Keep if arrival is in the future or strictly today
                return Date() <= lastStop.arr_time_eff || Calendar.current.isDateInToday(lastStop.arr_time_eff)
            }
    }
    
    var body: some View {
        NavigationStack {
            // 4. Use a List instead of ScrollView for better Watch performance
            List {
                if today_trains.isEmpty {
                    Text("No trains today")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(today_trains) { train in
                        // 5. Pass the "linked" data to the row view
                        let activeStops = stopsByTrain[train.id] ?? []
                        
                        WatchTrainRow(train: train, stops: activeStops)
                    }
                }
            }
            .navigationTitle("Rail")
        }
    }
}

// MARK: - Subview for the List Row
struct WatchTrainRow: View {
    let train: Train
    let stops: [Stop]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Treno \(train.number)")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if let firstStop = stops.first, let lastStop = stops.last {
                Text("\(firstStop.name) → \(lastStop.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Example: Show delay if present
            if train.delay > 0 {
                Text("Delay: \(train.delay) min")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
