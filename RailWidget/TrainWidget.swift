import WidgetKit
import SwiftUI
import SwiftData
import os

// MARK: - Train Widget Data Struct
struct TrainWidgetData {
    let trainID: UUID
    let logo: String
    let number: String
    let issue: String
    let delay: Int
    
    let firstStopName: String
    let firstStopDepTimeEff: Date
    let firstStopDepTimeId: Date
    let firstStopDepDelay: Int
    let firstStopPlatform: String
    
    let lastStopName: String
    let lastStopArrTimeEff: Date
    let lastStopArrTimeId: Date
    let lastStopArrDelay: Int
    let lastStopPlatform: String
    
    // Status helpers
    var isCancelled: Bool { issue == "Treno cancellato" }
}

// MARK: - Train Entry
struct TrainEntry: TimelineEntry {
    let date: Date
    let data: TrainWidgetData?
}

// MARK: - Train Provider
struct TrainProvider: TimelineProvider {
    typealias Entry = TrainEntry

    private static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "TrainWidget")

    @MainActor
    func fetchActiveTrain() -> TrainWidgetData? {
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
                let stops: [Stop]
            }
            
            var candidates: [TrainWithTimes] = []
            
            for train in allTrains {
                let trainID = train.id
                let stopDescriptor = FetchDescriptor<Stop>(predicate: #Predicate<Stop> { $0.id == trainID })
                let stops = try context.fetch(stopDescriptor)
                let selectedStops = stops.filter { $0.is_selected }.sorted(by: { $0.ref_time < $1.ref_time })
                
                if let first = selectedStops.first, let last = selectedStops.last {
                    candidates.append(TrainWithTimes(train: train, firstDep: first.dep_time_eff, lastArr: last.arr_time_eff, stops: stops))
                }
            }
            
            // 2. Sort candidates by their departure time
            let sortedCandidates = candidates.sorted(by: { $0.firstDep < $1.firstDep })
            
            // 3. The active train is the first one that hasn't arrived yet
            if let activeCandidate = sortedCandidates.first(where: { now < $0.lastArr }) {
                let train = activeCandidate.train
                let stops = activeCandidate.stops
                
                let summary = StopSummary.calculate(for: train.id, in: stops)
                
                return TrainWidgetData(
                    trainID: train.id,
                    logo: train.logo,
                    number: train.number,
                    issue: train.issue,
                    delay: train.delay,
                    firstStopName: summary.firstNoIssues.name,
                    firstStopDepTimeEff: summary.firstNoIssues.dep_time_eff,
                    firstStopDepTimeId: summary.firstNoIssues.dep_time_id,
                    firstStopDepDelay: summary.firstNoIssues.dep_delay,
                    firstStopPlatform: summary.first.platform,
                    lastStopName: summary.lastNoIssues.name,
                    lastStopArrTimeEff: summary.lastNoIssues.arr_time_eff,
                    lastStopArrTimeId: summary.lastNoIssues.arr_time_id,
                    lastStopArrDelay: summary.lastNoIssues.arr_delay,
                    lastStopPlatform: summary.last.platform
                )
            }
        } catch {
            Self.logger.error("Failed to load train widget data: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func placeholder(in context: Context) -> TrainEntry {
        TrainEntry(
            date: Date(),
            data: TrainWidgetData(
                trainID: UUID(),
                logo: "FR",
                number: "9612",
                issue: "",
                delay: 5,
                firstStopName: "Roma Termini",
                firstStopDepTimeEff: Date().addingTimeInterval(-3600),
                firstStopDepTimeId: Date().addingTimeInterval(-3600),
                firstStopDepDelay: 0,
                firstStopPlatform: "10",
                lastStopName: "Milano Centrale",
                lastStopArrTimeEff: Date().addingTimeInterval(3600),
                lastStopArrTimeId: Date().addingTimeInterval(3600),
                lastStopArrDelay: 5,
                lastStopPlatform: "3"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainEntry) -> ()) {
        Task {
            let data = await fetchActiveTrain()
            let entry = TrainEntry(date: Date(), data: data)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainEntry>) -> ()) {
        Task {
            let data = await fetchActiveTrain()
            let entry = TrainEntry(date: Date(), data: data)
            // Update every 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Train Widget View
struct TrainWidgetEntryView: View {
    var entry: TrainProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let data = entry.data {
                VStack(spacing: 8) {
                    // MARK: - logo + number
                    HStack(alignment: .center, spacing: 8) {
                        Image(data.logo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 24)
                        
                        Text(data.number)
                            .font(.title3).fontWeight(.semibold).fontDesign(widgetFontDesign)
                            .foregroundStyle(Color.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    
                    Spacer()
                    
                    // MARK: - departure and arrival stops
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(data.firstStopName)
                                .fontDesign(widgetFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                            
                            timeView(eff: data.firstStopDepTimeEff, id: data.firstStopDepTimeId, delay: data.firstStopDepDelay, isCancelled: data.isCancelled)
                        }
                        
                        HStack {
                            Text(data.lastStopName)
                                .fontDesign(widgetFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                            
                            timeView(eff: data.lastStopArrTimeEff, id: data.lastStopArrTimeId, delay: data.lastStopArrDelay, isCancelled: data.isCancelled, isArrival: true, firstDepId: data.firstStopDepTimeId)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                    
                    Spacer(minLength: 0)
                    
                    // MARK: - bottom bar
                    bottomBar(data: data)
                }
                .padding(12)
            } else {
                ContentUnavailableView("No active train", systemImage: "train.side.front.car")
                    .fontDesign(widgetFontDesign)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "railapp://view-train?trainID=\(entry.data?.trainID.uuidString ?? "")"))
    }
    
    @ViewBuilder
    private func timeView(eff: Date, id: Date, delay: Int, isCancelled: Bool, isArrival: Bool = false, firstDepId: Date = .distantPast) -> some View {
        let now = Date()
        let color: Color = {
            if isCancelled { return .red }
            if now >= (isArrival ? firstDepId : id) && delay != 0 {
                return delay > 0 ? .red : .green
            }
            if isArrival && now >= firstDepId && delay == 0 {
                return .green
            }
            if !isArrival && now >= id && delay == 0 {
                return .green
            }
            return .primary
        }()
        
        Text((isCancelled || (now >= (isArrival ? firstDepId : id) && delay != 0)) ? eff : id, format: .dateTime.hour().minute())
            .fontDesign(widgetFontDesign)
            .foregroundStyle(color)
            .monospacedDigit()
    }
    
    @ViewBuilder
    private func bottomBar(data: TrainWidgetData) -> some View {
        if data.isCancelled {
            ZStack {
                Text(data.issue)
                    .font(.subheadline)
                    .fontDesign(widgetFontDesign)
                    .foregroundStyle(Color.red)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.15))
            .cornerRadius(16)
        } else if Date() < data.firstStopDepTimeId {
            HStack(spacing: 8) {
                let depTime = data.firstStopDepTimeEff != .distantPast && Calendar.current.isDateInToday(data.firstStopDepTimeEff) ? data.firstStopDepTimeEff : data.firstStopDepTimeId
                let timeToDeparture = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: depTime)
                let day = timeToDeparture.day ?? 0
                let hour = timeToDeparture.hour ?? 0
                let minute = timeToDeparture.minute ?? 0
                
                let timeString: String = {
                    if day > 0 {
                        return "\(NSLocalizedString("Departure on", comment: "")) \(depTime.formatted(date: .abbreviated, time: .omitted))"
                    } else if hour > 0 && minute > 0 {
                        return "\(NSLocalizedString("Departure in", comment: "")) \(hour)h \(minute)m"
                    } else if hour > 0 && minute == 0 {
                        return "\(NSLocalizedString("Departure in", comment: "")) \(hour)h"
                    } else if minute > 0 {
                        return "\(NSLocalizedString("Departure in", comment: "")) \(minute)m"
                    } else {
                        return NSLocalizedString("Departure now", comment: "")
                    }
                }()
                
                ZStack {
                    Text(timeString)
                        .font(.subheadline)
                        .fontDesign(widgetFontDesign)
                        .padding(.vertical, 8).padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(16)
                
                if data.firstStopPlatform != "-" {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                        Text(data.firstStopPlatform)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(widgetFontDesign)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Color.yellow.opacity(0.5))
                    .cornerRadius(16)
                }
            }
        } else {
            HStack(spacing: 8) {
                let delayString: String = {
                    if data.delay < 0 {
                        let delay = abs(data.delay)
                        if delay >= 60 {
                            return "\(NSLocalizedString("Early of", comment: "")) \(delay / 60)h \(delay % 60)m"
                        }
                        return "\(NSLocalizedString("Early of", comment: "")) \(delay)m"
                    } else if data.delay == 0 {
                        return NSLocalizedString("On time", comment: "")
                    } else {
                        if data.delay >= 60 {
                            return "\(NSLocalizedString("Late of", comment: "")) \(data.delay / 60)h \(data.delay % 60)m"
                        }
                        return "\(NSLocalizedString("Late of", comment: "")) \(data.delay)m"
                    }
                }()
                
                ZStack {
                    Text(delayString)
                        .font(.subheadline)
                        .fontDesign(widgetFontDesign)
                        .foregroundStyle(data.delay > 0 ? .red : .green)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(data.delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .cornerRadius(16)
                
                if data.lastStopPlatform != "-" {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right")
                        Text(data.lastStopPlatform)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(widgetFontDesign)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Color.yellow.opacity(0.5))
                    .cornerRadius(16)
                }
            }
        }
    }
}

// MARK: - Train Widget Definition
struct TrainWidget: Widget {
    let kind: String = "TrainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainProvider()) { entry in
            TrainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Active Train")
        .description("Displays real-time info for your active train journey.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews
// MARK: - Previews
#Preview("Active: Late", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "R",
            number: "9612",
            issue: "",
            delay: 5,
            firstStopName: "Roma Termini",
            firstStopDepTimeEff: Date().addingTimeInterval(-1800),
            firstStopDepTimeId: Date().addingTimeInterval(-1800),
            firstStopDepDelay: 0,
            firstStopPlatform: "10",
            lastStopName: "Milano Centrale",
            lastStopArrTimeEff: Date().addingTimeInterval(3600),
            lastStopArrTimeId: Date().addingTimeInterval(3600),
            lastStopArrDelay: 5,
            lastStopPlatform: "3"
        )
    )
}

#Preview("Active: On Time", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "FR",
            number: "9511",
            issue: "",
            delay: 0,
            firstStopName: "Milano Centrale",
            firstStopDepTimeEff: Date().addingTimeInterval(-3600),
            firstStopDepTimeId: Date().addingTimeInterval(-3600),
            firstStopDepDelay: 0,
            firstStopPlatform: "14",
            lastStopName: "Salerno",
            lastStopArrTimeEff: Date().addingTimeInterval(7200),
            lastStopArrTimeId: Date().addingTimeInterval(7200),
            lastStopArrDelay: 0,
            lastStopPlatform: "1"
        )
    )
}

#Preview("Active: Early", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "ITALO",
            number: "8902",
            issue: "",
            delay: -3,
            firstStopName: "Napoli Centrale",
            firstStopDepTimeEff: Date().addingTimeInterval(-1200),
            firstStopDepTimeId: Date().addingTimeInterval(-1200),
            firstStopDepDelay: 0,
            firstStopPlatform: "12",
            lastStopName: "Roma Termini",
            lastStopArrTimeEff: Date().addingTimeInterval(600),
            lastStopArrTimeId: Date().addingTimeInterval(900),
            lastStopArrDelay: -3,
            lastStopPlatform: "24"
        )
    )
}

#Preview("Upcoming: Imminent", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "FR",
            number: "9422",
            issue: "",
            delay: 0,
            firstStopName: "Venezia Santa Lucia",
            firstStopDepTimeEff: Date().addingTimeInterval(120),
            firstStopDepTimeId: Date().addingTimeInterval(120),
            firstStopDepDelay: 0,
            firstStopPlatform: "8",
            lastStopName: "Firenze S.M.N.",
            lastStopArrTimeEff: Date().addingTimeInterval(7200),
            lastStopArrTimeId: Date().addingTimeInterval(7200),
            lastStopArrDelay: 0,
            lastStopPlatform: "16"
        )
    )
}

#Preview("Upcoming: Normal", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "ITALO",
            number: "9924",
            issue: "",
            delay: 0,
            firstStopName: "Torino Porta Nuova",
            firstStopDepTimeEff: Date().addingTimeInterval(3600),
            firstStopDepTimeId: Date().addingTimeInterval(3600),
            firstStopDepDelay: 0,
            firstStopPlatform: "3",
            lastStopName: "Roma Termini",
            lastStopArrTimeEff: Date().addingTimeInterval(14400),
            lastStopArrTimeId: Date().addingTimeInterval(14400),
            lastStopArrDelay: 0,
            lastStopPlatform: "12"
        )
    )
}

#Preview("Cancelled", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "FR",
            number: "9310",
            issue: "Treno cancellato",
            delay: 0,
            firstStopName: "Bari Centrale",
            firstStopDepTimeEff: Date().addingTimeInterval(1800),
            firstStopDepTimeId: Date().addingTimeInterval(1800),
            firstStopDepDelay: 0,
            firstStopPlatform: "-",
            lastStopName: "Roma Termini",
            lastStopArrTimeEff: Date().addingTimeInterval(12600),
            lastStopArrTimeId: Date().addingTimeInterval(12600),
            lastStopArrDelay: 0,
            lastStopPlatform: "-"
        )
    )
}

#Preview("Long Names", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: TrainWidgetData(
            trainID: UUID(),
            logo: "ITALO",
            number: "9924",
            issue: "",
            delay: 0,
            firstStopName: "Reggio Emilia - Mediopadana Stazione Centrale",
            firstStopDepTimeEff: Date().addingTimeInterval(3600),
            firstStopDepTimeId: Date().addingTimeInterval(3600),
            firstStopDepDelay: 0,
            firstStopPlatform: "13",
            lastStopName: "Bolzano Bozen Hauptbahnhof - Stazione Centrale",
            lastStopArrTimeEff: Date().addingTimeInterval(28800),
            lastStopArrTimeId: Date().addingTimeInterval(28800),
            lastStopArrDelay: 0,
            lastStopPlatform: "4"
        )
    )
}

#Preview("No Active Train", as: .systemMedium) {
    TrainWidget()
} timeline: {
    TrainEntry(
        date: .now,
        data: nil
    )
}
