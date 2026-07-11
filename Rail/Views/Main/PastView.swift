import SwiftUI
import SwiftData
import StoreKit

struct PastView: View {
    // MARK: - Properties
    // enviroment variables
    @Environment(\.requestReview) var request_review
    
    // deep link variables
    @Binding var ticketTrainID: UUID?
    @Binding var ticketSeatID: UUID?
    @Binding var show_ticket_view: Bool
    @Binding var searchText: String
    @Binding var navigationPath: [Train]
    
    // database variables
    @Environment(\.modelContext) private var model_context
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]

    // sheet variables
    @State private var rowItems: [TrainRowItem] = []
    @State private var stopsByTrain: [UUID: [Stop]] = [:]

    private var filteredRowItems: [TrainRowItem] {
        rowItems.filter { TrainListBuilder.matches($0, searchText: searchText) }
    }

    // MARK: - Body
    var body: some View {
        Group {
            if filteredRowItems.isEmpty {
                if rowItems.isEmpty {
                    ContentUnavailableView("No past journeys",
                                           systemImage: "exclamationmark.magnifyingglass",
                                           description: Text("Add a new journey by tapping the button below."))
                    .padding()
                    .fontDesign(app_font_design)
                    .foregroundColor(Color.primary)
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
                            ZStack {
                                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: context.date)

                                NavigationLink(value: item.train) {
                                    EmptyView()
                                }
                                .buttonStyle(.plain)
                                .opacity(0)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: delete_past_trains)
                    }
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
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
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: request_review)
            refreshRowItems()
        }
        .onChange(of: trains.count) { _, _ in refreshRowItems() }
        .onChange(of: stops.count) { _, _ in refreshRowItems() }
        .onChange(of: navigationPath.count) { _, _ in refreshRowItems() }
    }
    
    private func refreshRowItems() {
        stopsByTrain = Dictionary(grouping: stops, by: \.id)
        rowItems = TrainListBuilder.pastItems(trains: trains, stops: stops)
    }
    
    // MARK: - Functions
    private func delete_past_trains(at offsets: IndexSet) {
        let items = offsets.map { filteredRowItems[$0] }
        for item in items {
            Task {
                await CalendarManager.shared.removeTrainEvent(train: item.train)
            }
            
            let relatedStops = stops.filter { $0.id == item.train.id }
            relatedStops.forEach { model_context.delete($0) }
            model_context.delete(item.train)
        }
        refreshRowItems()
    }
}
