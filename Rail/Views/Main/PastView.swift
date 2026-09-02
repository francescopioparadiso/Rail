import SwiftUI
import SwiftData
import StoreKit

struct PastView: View {
    @Environment(\.requestReview) var requestReview
    
    @Binding var ticketTrainID: UUID?
    @Binding var ticketSeatID: UUID?
    @Binding var showTicketView: Bool
    @Binding var searchText: String
    @Binding var navigationPath: [Train]
    var isActive: Bool = true
    
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    @State private var rowItems: [TrainRowItem] = []
    @State private var listNow = Date()
    @State private var stopsByTrain: [UUID: [Stop]] = [:]
    @State private var refreshTask: Task<Void, Never>?

    private var filteredRowItems: [TrainRowItem] {
        rowItems.filter { TrainListBuilder.matches($0, searchText: searchText) }
    }

    var body: some View {
        Group {
            if filteredRowItems.isEmpty {
                if rowItems.isEmpty {
                    ContentUnavailableView {
                        Label("No past journeys", systemImage: "exclamationmark.magnifyingglass")
                    } description: {
                        Text("Add a new journey by tapping the button below.")
                    } actions: {
                        Button {
                            Task {
                                refreshRowItems()
                            }
                        } label: {
                            Label("Refresh Network", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .fontDesign(appFontDesign)
                    .foregroundStyle(Color.secondary)
                } else {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("No trains match \"\(searchText)\".")
                    )
                    .padding()
                    .foregroundStyle(Color.secondary)
                    .fontDesign(appFontDesign)
                }
            } else {
                List {
                    ForEach(groupedRowSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                PastTrainRow(
                                    item: item,
                                    now: listNow,
                                    isFirst: item.id == section.items.first?.id,
                                    isLast: item.id == section.items.last?.id
                                )
                                .equatable()
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in
                                deletePastTrains(at: offsets, in: section.items)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .listStyle(.insetGrouped)
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
        .background(appBackgroundColor)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
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
    
    /// Past journeys grouped by the month they ran in, newest first — the same
    /// grouping the email ticket list uses.
    private var groupedRowSections: [(title: String, items: [TrainRowItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRowItems) { item -> Date in
            let date = item.summary.lastNoIssues.arr_time_eff
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
        return grouped.keys.sorted(by: >).map { key in
            let items = (grouped[key] ?? []).sorted {
                $0.summary.lastNoIssues.arr_time_eff > $1.summary.lastNoIssues.arr_time_eff
            }
            return (monthSectionTitle(for: key), items)
        }
    }

    private func deletePastTrains(at offsets: IndexSet, in sectionItems: [TrainRowItem]) {
        let items = offsets.compactMap { sectionItems.indices.contains($0) ? sectionItems[$0] : nil }
        for item in items {
            Task {
                await CalendarManager.shared.removeTrainEvent(train: item.train)
            }
            
            let relatedStops = stops.filter { $0.id == item.train.id }
            relatedStops.forEach { modelContext.delete($0) }
            modelContext.delete(item.train)
        }
        refreshRowItems()
    }
}
