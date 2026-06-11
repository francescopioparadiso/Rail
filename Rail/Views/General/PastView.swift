import SwiftUI
import SwiftData
import StoreKit

struct PastView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var request_review
    
    // deep link variables
    @Binding var ticketTrainID: UUID?
    @Binding var ticketSeatID: UUID?
    @Binding var show_ticket_view: Bool
    
    // database variables
    @Environment(\.modelContext) private var model_context
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    // sheet variables
    @State private var add_journey_sheet = false
    @State private var navigationPath: [Train] = []

    // computed variables
    private var past_trains: [Train] {
        let now = Date()
        let calendar = Calendar.current
        let stopsByTrain = Dictionary(grouping: stops, by: { $0.id })
        
        return trains
            .filter { train in
                guard let trainStops = stopsByTrain[train.id] else { return false }
                let sortedStops = trainStops.sorted(by: { $0.ref_time < $1.ref_time })
                guard let lastStop = sortedStops.last else { return false }
                return now > lastStop.arr_time_eff && !calendar.isDateInToday(lastStop.arr_time_eff)
            }
            .sorted { lhs, rhs in
                let lhsLast = stopsByTrain[lhs.id]?.max(by: { $0.ref_time < $1.ref_time })
                let rhsLast = stopsByTrain[rhs.id]?.max(by: { $0.ref_time < $1.ref_time })
                
                guard let lTime = lhsLast?.arr_time_eff, let rTime = rhsLast?.arr_time_eff else { return false }
                return lTime > rTime
            }
    }

    // MARK: - main view
    var body: some View {
        NavigationStack(path: $navigationPath) {
            if past_trains.isEmpty {
                ContentUnavailableView("No past journeys",
                                       systemImage: "exclamationmark.magnifyingglass",
                                       description: Text("Add a new journey by tapping the button below."))
                .padding()
                .fontDesign(app_font_design)
                .foregroundColor(Color.primary)
            } else {
                let stopsByTrain = Dictionary(grouping: stops, by: { $0.id })
                
                List {
                    ForEach(past_trains) { train in
                        let trainStops = (stopsByTrain[train.id] ?? [])
                            .sorted(by: { $0.ref_time < $1.ref_time })
                        
                        let summary = StopSummary.calculate(for: train.id, in: trainStops)

                        ZStack {
                            ListView(train: train, stops: trainStops, summary: summary)

                            NavigationLink(value: train) {
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
                .navigationDestination(for: Train.self) { train in
                    let trainStops = stops.filter { $0.id == train.id }.sorted(by: { $0.ref_time < $1.ref_time })
                    let trainSeats = seats.filter { $0.trainID == train.id }
                    DetailsView(train: train, stops: trainStops, seats: trainSeats, show_ticket_initially: $show_ticket_view, ticketSeatID: $ticketSeatID)
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
            AddTrainView()
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
            // Remove calendar event
            Task {
                await CalendarManager.shared.removeTrainEvent(train: train)
            }
            
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
        let trainStops = stops.filter { $0.id == train.id }.sorted(by: { $0.ref_time < $1.ref_time })
        for (i, stop) in trainStops.enumerated() {
            if i == 0 {
                // first station
                if Date() < stop.dep_time_id {
                    stop.is_completed = false
                    stop.is_in_station = true
                } else {
                    stop.is_completed = true
                    stop.is_in_station = false
                }
            } else if i == trainStops.count - 1 {
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
