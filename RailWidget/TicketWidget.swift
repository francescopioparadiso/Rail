import WidgetKit
import SwiftUI
import SwiftData
import os

// MARK: - Ticket Entry
struct TicketEntry: TimelineEntry {
    let date: Date
    let trainID: UUID?
    let seatID: UUID?
    let trainNumber: String?
    let trainLogo: String?
    let ownerName: String?
    let carriage: String?
    let seatNumber: String?
    let qrCode: Data?
}

// MARK: - Ticket Provider
struct TicketProvider: TimelineProvider {
    typealias Entry = TicketEntry

    private static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "TicketWidget")

    @MainActor
    func fetchActiveTicket() -> (trainID: UUID?, seatID: UUID?, trainNumber: String?, logo: String?, owner: String?, carriage: String?, seat: String?, qrCode: Data?) {
        do {
            let container = try SharedSwiftData.makeReadOnlyContainer()
            let context = container.mainContext
            
            let now = Date()
            
            // 1. Fetch all trains and their relevant stops to determine which is active
            let trainDescriptor = FetchDescriptor<Train>()
            let allTrains = try context.fetch(trainDescriptor)
            
            struct TrainWithTimes {
                let train: Train
                let firstDep: Date
                let lastArr: Date
            }
            
            var candidates: [TrainWithTimes] = []
            
            for train in allTrains {
                let trainID = train.id
                let stopDescriptor = FetchDescriptor<Stop>(predicate: #Predicate<Stop> { $0.id == trainID })
                let stops = try context.fetch(stopDescriptor)
                let selectedStops = stops.filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
                
                if let first = selectedStops.first, let last = selectedStops.last {
                    candidates.append(TrainWithTimes(train: train, firstDep: first.dep_time_eff, lastArr: last.arr_time_eff))
                }
            }
            
            // 2. Sort candidates by their departure time
            let sortedCandidates = candidates.sorted(by: { $0.firstDep < $1.firstDep })
            
            // 3. The active train is the first one that hasn't arrived yet
            if let activeCandidate = sortedCandidates.first(where: { now < $0.lastArr }) {
                let train = activeCandidate.train
                let trainID = train.id
                
                // 4. Fetch first seat for this train
                let seatDescriptor = FetchDescriptor<Seat>(predicate: #Predicate<Seat> { $0.trainID == trainID })
                let seats = try context.fetch(seatDescriptor)
                let firstSeat = seats.first
                
                return (
                    trainID,
                    firstSeat?.id,
                    train.number,
                    train.logo,
                    firstSeat?.name,
                    firstSeat?.carriage,
                    firstSeat?.number,
                    scaleImage(data: firstSeat?.image, to: 400)
                )
            }
        } catch {
            Self.logger.error("Failed to load ticket widget data: \(error.localizedDescription, privacy: .public)")
        }
        return (nil, nil, nil, nil, nil, nil, nil, nil)
    }

    func placeholder(in context: Context) -> TicketEntry {
        TicketEntry(
            date: Date(),
            trainID: UUID(),
            seatID: UUID(),
            trainNumber: "9612",
            trainLogo: "FR",
            ownerName: "Francesco",
            carriage: "5",
            seatNumber: "12A",
            qrCode: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TicketEntry) -> ()) {
        Task {
            let data = await fetchActiveTicket()
            let entry = TicketEntry(
                date: Date(),
                trainID: data.trainID,
                seatID: data.seatID,
                trainNumber: data.trainNumber,
                trainLogo: data.logo,
                ownerName: data.owner,
                carriage: data.carriage,
                seatNumber: data.seat,
                qrCode: data.qrCode
            )
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicketEntry>) -> ()) {
        Task {
            let data = await fetchActiveTicket()
            let entry = TicketEntry(
                date: Date(),
                trainID: data.trainID,
                seatID: data.seatID,
                trainNumber: data.trainNumber,
                trainLogo: data.logo,
                ownerName: data.owner,
                carriage: data.carriage,
                seatNumber: data.seat,
                qrCode: data.qrCode
            )
            // Update every 15 minutes or when it ends
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Ticket Widget View
struct TicketWidgetEntryView: View {
    // MARK: - Properties

    var entry: TicketProvider.Entry
    @Environment(\.widgetFamily) var family

    // MARK: - Body

    var body: some View {
        Group {
            if let trainNumber = entry.trainNumber {
                if entry.qrCode != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    if let logo = entry.trainLogo {
                                        Image(logo)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 12)
                                    } else {
                                        Image(systemName: "train.side.front.car")
                                    }
                                    Text(trainNumber)
                                }
                                .font(.footnote).fontWeight(.medium).fontDesign(widgetFontDesign)
                                .foregroundStyle(.secondary)
                                    
                                Divider()
                            }
                            
                            Text(entry.ownerName ?? "No owner")
                                .font(.title).fontWeight(.semibold).fontDesign(widgetFontDesign)
                                .lineLimit(1).truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                if let carriage = entry.carriage, !carriage.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "train.side.front.car")
                                        Text(carriage)
                                    }
                                    .font(.subheadline).fontWeight(.semibold).fontDesign(widgetFontDesign)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(.primary)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                }

                                if let seatNumber = entry.seatNumber, !seatNumber.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "figure.seated.seatbelt")
                                        Text(seatNumber)
                                    }
                                    .font(.subheadline).fontWeight(.semibold).fontDesign(widgetFontDesign)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(.primary)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if let imageData = entry.qrCode, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(16)
                        } else {
                            ContentUnavailableView {
                                Label("No QR", systemImage: "qrcode.viewfinder")
                            }
                            .scaleEffect(0.8)
                        }
                    }
                } else {
                    ContentUnavailableView("No QR code found for train \(trainNumber)", systemImage: "ticket.fill")
                        .fontDesign(widgetFontDesign)
                        .lineLimit(1).truncationMode(.tail)
                        .minimumScaleFactor(0.5)
                }
            } else {
                ContentUnavailableView("No active train", systemImage: "train.side.front.car")
                    .fontDesign(widgetFontDesign)
                    .lineLimit(1).truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(ticketWidgetURL(for: entry))
    }

    // MARK: - Actions

    private func ticketWidgetURL(for entry: TicketEntry) -> URL? {
        guard let trainID = entry.trainID else { return nil }
        var components = URLComponents()
        components.scheme = "railapp"
        components.host = "view-ticket"
        var queryItems = [URLQueryItem(name: "trainID", value: trainID.uuidString)]
        if let seatID = entry.seatID {
            queryItems.append(URLQueryItem(name: "seatID", value: seatID.uuidString))
        }
        components.queryItems = queryItems
        return components.url
    }
}

// MARK: - Ticket Widget Definition
struct TicketWidget: Widget {
    let kind: String = "TicketWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicketProvider()) { entry in
            TicketWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Active Ticket")
        .description("Displays the QR code and seat info for your active train journey.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Previews
#Preview("Active Ticket", as: .systemMedium) {
    TicketWidget()
} timeline: {
    TicketEntry(
        date: .now,
        trainID: UUID(),
        seatID: UUID(),
        trainNumber: "9612",
        trainLogo: "ITALO",
        ownerName: "Francesco",
        carriage: "5",
        seatNumber: "12A",
        qrCode: scaleImage(data: UIImage(named: "sample_code")?.pngData(), to: 400)
    )
}

#Preview("No Ticket", as: .systemMedium) {
    TicketWidget()
} timeline: {
    TicketEntry(
        date: .now,
        trainID: UUID(),
        seatID: UUID(),
        trainNumber: "9612",
        trainLogo: "ITALO",
        ownerName: nil,
        carriage: nil,
        seatNumber: nil,
        qrCode: nil
    )
}

#Preview("No Active Train", as: .systemMedium) {
    TicketWidget()
} timeline: {
    TicketEntry(
        date: .now,
        trainID: nil,
        seatID: nil,
        trainNumber: nil,
        trainLogo: nil,
        ownerName: nil,
        carriage: nil,
        seatNumber: nil,
        qrCode: nil
    )
}
