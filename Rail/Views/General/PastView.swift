import SwiftUI
import SwiftData

struct PastView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var request_review
    
    // database variables
    @Environment(\.modelContext) private var model_context
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    // sheet variables
    @State private var add_journey_sheet = false

    // computed variables
    private var past_trains: [Train] {
        trains
            .filter { train in
                let train_stops = stops
                    .filter { $0.id == train.id }
                    .sorted(by: { $0.ref_time < $1.ref_time })
                
                guard let last_stop = train_stops.last else { return false }
                return Date() > last_stop.arr_time_eff && !Calendar.current.isDateInToday(last_stop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                guard
                    let lhs_last_stop = stops
                        .filter({ $0.id == lhs.id })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .last,
                    let rhs_last_stop = stops
                        .filter({ $0.id == rhs.id })
                        .sorted(by: { $0.ref_time < $1.ref_time })
                        .last
                else { return false }
                
                return lhs_last_stop.arr_time_eff > rhs_last_stop.arr_time_eff
            }
    }

    // MARK: - main view
    var body: some View {
        NavigationStack {
            if past_trains.isEmpty {
                ContentUnavailableView("No past journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the button below."))
                .padding()
                .fontDesign(app_font_design)
                .foregroundColor(Color.primary)
            } else {
                List {
                    ForEach(past_trains) { train in
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

                        ZStack {
                            ListView(train: train, stops: trainStops)

                            NavigationLink(destination: DetailsView(train: train, stops: trainStops, seats: trainSeats)) {
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
            }
        }
        .sheet(isPresented: $add_journey_sheet) {
            AddTrainView(add_favorite_sheet: false)
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: request_review)
            update_past_trains()
        }
    }
    
    // MARK: - functions
    private func delete_past_trains(at offsets: IndexSet) {
        let items = offsets.map { past_trains[$0] }
        for train in items {
            let relatedStops = stops.filter { $0.id == train.id }
            relatedStops.forEach { model_context.delete($0) }
            model_context.delete(train)
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
