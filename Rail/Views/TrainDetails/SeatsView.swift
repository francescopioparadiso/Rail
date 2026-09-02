import SwiftUI
import SwiftData
import WidgetKit
import StoreKit

struct SeatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) private var modelContext
    @Query private var allSeats: [Seat]
    @Query private var profiles: [UserProfile]

    let train: Train
    let seats: [Seat]
    let initialSeatID: UUID?

    @State private var searchText = ""
    @State private var seatFormPresentation: SeatFormPresentation? = nil

    private enum SeatFormPresentation: Identifiable {
        case new
        case edit(Seat)

        var id: String {
            switch self {
            case .new:
                return "new"
            case .edit(let seat):
                return seat.id.uuidString
            }
        }

        var seatToEdit: Seat? {
            if case .edit(let seat) = self { return seat }
            return nil
        }
    }

    private var namePlaceholder: String {
        var nameCount: [String: Int] = [:]
        for seat in allSeats {
            nameCount[seat.name, default: 0] += 1
        }
        return nameCount.max(by: { $0.value < $1.value })?.key ?? ""
    }

    private var sortedSeats: [Seat] {
        seats.sorted { lhs, rhs in
            if lhs.carriage != rhs.carriage {
                return lhs.carriage.localizedStandardCompare(rhs.carriage) == .orderedAscending
            } else if lhs.number != rhs.number {
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedAscending
            } else {
                return lhs.name < rhs.name
            }
        }
    }

    private var filteredSeats: [Seat] {
        sortedSeats.filter { matches($0, searchText: searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if seats.isEmpty {
                    ContentUnavailableView(
                        "No seats added",
                        systemImage: "airplaneseat",
                        description: Text("Add a new seat using the button below.")
                    )
                    .foregroundStyle(.secondary)
                    .fontDesign(appFontDesign)
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredSeats.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(Color.secondary)
                        .fontDesign(appFontDesign)
                } else {
                    List {
                        Section {
                            ForEach(filteredSeats) { seat in
                                seatRow(seat: seat)
                            }
                            .onDelete { offsets in
                                deleteSeats(at: offsets, from: filteredSeats)
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Text(filteredSeats.count, format: .number)
                                    .contentTransition(.numericText(value: Double(filteredSeats.count)))
                                Text(filteredSeats.count == 1 ? "seat" : "seats")
                            }
                            .animation(.snappy, value: filteredSeats.count)
                        }
                        .fontDesign(appFontDesign)
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Your Seats")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                DefaultToolbarItem(kind: .search, placement: .bottomBar)

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        HapticFeedback.confirm()
                        seatFormPresentation = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search seats")
            .sheet(item: $seatFormPresentation) { presentation in
                SeatFormSheet(
                    train: train,
                    seatToEdit: presentation.seatToEdit,
                    namePlaceholder: namePlaceholder,
                    isFirstSeatForTrain: seats.isEmpty && presentation.seatToEdit == nil,
                    accountName: profiles.primary?.name ?? ""
                )
                .presentationDetents([.large])
            }
            .onAppear {
                ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)

                if let initialID = initialSeatID, let seat = seats.first(where: { $0.id == initialID }) {
                    seatFormPresentation = .edit(seat)
                }
            }
        }
        .background(appBackgroundColor.ignoresSafeArea())
    }

    private func matches(_ seat: Seat, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableFields = [
            seat.name,
            seat.carriage,
            seat.number,
        ]

        return searchableFields.contains { $0.lowercased().contains(query) }
    }

    @ViewBuilder
    private func seatRow(seat: Seat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(seat.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !seat.carriage.isEmpty && !seat.number.isEmpty {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "train.side.rear.car")
                            Text(seat.carriage)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 64)

                        HStack(spacing: 8) {
                            Image(systemName: "carseat.left.fill")
                            Text(seat.number)
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
            }
            .fontDesign(appFontDesign)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.tap()
            seatFormPresentation = .edit(seat)
        }
    }

    private func deleteSeats(at offsets: IndexSet, from list: [Seat]) {
        withAnimation(.snappy) {
            for index in offsets {
                modelContext.delete(list[index])
            }
            try? modelContext.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview("Populated List") {
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    let mockTrain = Train(
        id: UUID(),
        logo: "trenitalia",
        number: "9607",
        identifier: "FR9607",
        provider: "trenitalia",
        last_update_time: Date(),
        delay: 0,
        direction: "Napoli Centrale",
        issue: ""
    )

    let seat1 = Seat(id: UUID(), trainID: mockTrain.id, name: "Pierpaolo", carriage: "1", number: "2D", image: UIImage(named: "sample_code")?.pngData())
    let seat2 = Seat(id: UUID(), trainID: mockTrain.id, name: "Davide", carriage: "1", number: "7B", image: UIImage(named: "sample_code")?.pngData())
    let seat3 = Seat(id: UUID(), trainID: mockTrain.id, name: "Andrea", carriage: "1", number: "8C", image: UIImage(named: "sample_code")?.pngData())

    container.mainContext.insert(mockTrain)
    container.mainContext.insert(seat1)
    container.mainContext.insert(seat2)
    container.mainContext.insert(seat3)

    return SeatsView(train: mockTrain, seats: [seat1, seat2, seat3], initialSeatID: nil)
        .modelContainer(container)
        .environment(\.locale, Locale(identifier: "it"))
}

#Preview("Empty State") {
    let schema = Schema([Train.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    let mockTrain = Train(
        id: UUID(),
        logo: "italo",
        number: "9923",
        identifier: "IT9923",
        provider: "italo",
        last_update_time: Date(),
        delay: 5,
        direction: "Milano Centrale",
        issue: ""
    )

    container.mainContext.insert(mockTrain)

    return SeatsView(train: mockTrain, seats: [], initialSeatID: nil)
        .modelContainer(container)
}
