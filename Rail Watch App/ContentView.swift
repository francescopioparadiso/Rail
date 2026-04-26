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
    
    return ContentView()
        .modelContainer(container)
}
