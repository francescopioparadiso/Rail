import SwiftUI
import SwiftData

struct PastView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    @State private var add_journey_sheet = false

    private var past_trains: [Train] {
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
                        .filter({ $0.id == lhs.id })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first,
                    let rhsFirstStop = stops
                        .filter({ $0.id == rhs.id })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .first
                else { return false }
                
                return lhsFirstStop.dep_time_id > rhsFirstStop.dep_time_eff
            }
            .filter { train in
                let trainStops = stops
                    .filter { $0.id == train.id }
                    .sorted(by: { $0.ref_time < $1.ref_time })
                
                guard let lastStop = trainStops.last else { return false }
                return Date() > lastStop.arr_time_eff && !Calendar.current.isDateInToday(lastStop.arr_time_eff)
            }
    }

    
    var body: some View {
        NavigationStack {
            if past_trains.isEmpty {
                ContentUnavailableView("No past journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the above button."))
                .padding()
                .fontDesign(appFontDesign)
                .foregroundColor(Color.primary)
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
                    ForEach(past_trains) { train in
                        let trainStops = stops
                            .filter { $0.id == train.id }
                            .sorted(by: { $0.ref_time < $1.ref_time })

                        ZStack {
                            ListView(train: train, stops: trainStops)

                            NavigationLink(destination: DetailsView(train: train, stops: trainStops)) {
                                EmptyView()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(0)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: delete_past_trains)
                }
                .scrollIndicators(.hidden)
                .listStyle(.plain)
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
            update_past_trains()
        }
    }
    
    private func delete_past_trains(at offsets: IndexSet) {
        let items = offsets.map { past_trains[$0] }
        for train in items {
            let relatedStops = stops.filter { $0.id == train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(train)
        }
    }
    
    private func update_past_trains() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for train in past_trains {
                    group.addTask {
                        await update_train(train)
                    }
                }
            }
            print("🔄 \(past_trains.count) trains updated at \(Date().formatted(date: .abbreviated, time: .standard))")
        }
    }
    
    private func update_train(_ train: Train) async {
        for (i, stop) in stops.enumerated() {
            if i == 0 {
                // first station
                if Date() < stop.dep_time_id {
                    stop.is_completed = false
                    stop.is_in_station = true
                } else {
                    stop.is_completed = true
                    stop.is_in_station = false
                }
            } else if i == stops.count - 1 {
                // last station
                if Date() < stop.arr_time_eff {
                    stop.is_completed = false
                    stop.is_in_station = false
                } else {
                    train.delay = stop.arr_delay
                    stop.is_completed = true
                    stop.is_in_station = true
                }
            } else {
                // middle stations
                if Date() < stop.arr_time_eff {
                    stop.is_completed = false
                    stop.is_in_station = false
                } else if Date() >= stop.arr_time_eff && Date() < stop.dep_time_eff {
                    stop.is_completed = false
                    stop.is_in_station = true
                } else if Date() >= stop.dep_time_eff {
                    stop.is_completed = true
                    stop.is_in_station = true
                }
            }
        }
    }
}
