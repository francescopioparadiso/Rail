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
    var isActive: Bool = true
    
    // database variables
    @Environment(\.modelContext) private var model_context
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    // sheet variables
    @State private var rowItems: [TrainRowItem] = []
    @State private var listNow = Date()
    @State private var stopsByTrain: [UUID: [Stop]] = [:]
    @State private var refreshTask: Task<Void, Never>?

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
                List {
                    ForEach(filteredRowItems) { item in
                        PastTrainRow(item: item, now: listNow)
                            .equatable()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: delete_past_trains)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
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
            if rowItems.isEmpty {
                refreshRowItems()
            }
        }
        .onChange(of: trains.count) { _, _ in scheduleRefreshRowItems() }
        .onChange(of: stops.count) { _, _ in scheduleRefreshRowItems() }
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                listNow = Date()
            }
        }
    }

    private func scheduleRefreshRowItems() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            refreshRowItems()
        }
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
