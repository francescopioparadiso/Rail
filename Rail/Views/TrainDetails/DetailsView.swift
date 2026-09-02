import SwiftUI
import SwiftData
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import WidgetKit
import StoreKit

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct DetailsView: View {
    // MARK: - Properties

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    let train: Train
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    @Binding var showTicketInitially: Bool
    @Binding var ticketSeatID: UUID?

    @State private var seatsSheet: Bool = false
    @State private var pendingSeatID: UUID?
    @State private var showAllStops: Bool = false
    @State private var searchText = ""
    @State private var routeDistanceKm: Int?
    @State private var isFavorite: Bool = false
    @State private var isRefreshing = false
    @State private var stopSummary: StopSummary

    init(
        train: Train,
        showTicketInitially: Binding<Bool>,
        ticketSeatID: Binding<UUID?>
    ) {
        self.train = train
        let trainID = train.id
        _stops = Query(
            filter: #Predicate<Stop> { $0.id == trainID },
            sort: [SortDescriptor(\.ref_time)]
        )
        _seats = Query(
            filter: #Predicate<Seat> { $0.trainID == trainID }
        )
        self._showTicketInitially = showTicketInitially
        self._ticketSeatID = ticketSeatID
        self._stopSummary = State(initialValue: StopSummary.calculate(in: []))
    }

    // MARK: - Computed

    private var summary: StopSummary { stopSummary }

    private var baseStops: [Stop] {
        showAllStops ? stops : stops.filter { $0.is_selected }
    }

    /// True when the journey is today or already past.
    private var showsLastUpdate: Bool {
        let calendar = Calendar.current
        guard let departure = stops.sorted(by: { $0.ref_time < $1.ref_time }).first?.ref_time else { return false }
        return calendar.startOfDay(for: departure) <= calendar.startOfDay(for: Date())
    }

    private var filteredStops: [Stop] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return baseStops }
        return baseStops.filter { $0.name.lowercased().contains(query) }
    }

    private var showSpeed: Bool {
        return Date() <= summary.last.arr_time_eff || Calendar.current.isDateInToday(summary.last.arr_time_eff)
    }

    private var firstStop: Stop {
        showAllStops ?
        stops.first ?? Stop.placeholder() :
        summary.first
    }
    private var lastStop: Stop {
        showAllStops ?
        stops.last ?? Stop.placeholder() :
        summary.last
    }
    private var firstStopNoIssues: Stop {
        showAllStops ?
        stops.first(where: { $0.status != 3 }) ?? stops.first ?? Stop.placeholder() :
        summary.firstNoIssues
    }
    private var lastStopNoIssues: Stop {
        showAllStops ?
        stops.last(where: { $0.status != 3 }) ?? stops.last ?? Stop.placeholder() :
        summary.lastNoIssues
    }

    private var firstIndex: Int {
        stops.startIndex
    }
    private var lastIndex: Int {
        stops.indices.last ?? 0
    }
    private var firstIndexNoIssues: Int {
        stops.firstIndex(where: { $0.status != 3 }) ?? (stops.indices.first ?? 0)
    }
    private var lastIndexNoIssues: Int {
        stops.lastIndex(where: { $0.status != 3 }) ?? (stops.indices.last ?? 0)
    }

    private var normalizedIdentifier: String {
        train.identifier.contains("/") ?
            String(train.identifier.split(separator: "/").dropLast().joined(separator: "/")) :
            train.identifier
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // train logo and number
            HStack(spacing: 4) {
                Image(train.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                
                Text(train.number)
                    .font(.title3)
                    .fontDesign(appFontDesign)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.primary)
                
                Spacer()
            }
            .padding(.horizontal).padding(.top)
            
            // departure and arrival
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(firstStopNoIssues.name)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                        .strikethrough(train.issue == "Treno cancellato")
                    
                    Spacer()
                    
                    if train.issue == "Treno cancellato" {
                        Text(firstStopNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .strikethrough()
                            .foregroundStyle(Color.red)
                            .monospacedDigit()
                    } else if Date() >= firstStop.dep_time_id || Calendar.current.isDateInToday(firstStop.dep_time_id) {
                        HStack {
                            if firstStopNoIssues.dep_delay != 0 {
                                Text(firstStopNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .strikethrough()
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                            
                            Text(firstStopNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(firstStopNoIssues.dep_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        }
                    } else {
                        Text(firstStopNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Date() >= firstStopNoIssues.dep_time_id && firstStopNoIssues.dep_delay == 0 ? Color.green : Color.primary)
                            .monospacedDigit()
                    }
                }
                
                HStack {
                    Text(lastStopNoIssues.name)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                        .strikethrough(train.issue == "Treno cancellato")
                    
                    Spacer()
                    
                    if train.issue == "Treno cancellato" {
                        Text(lastStopNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .strikethrough()
                            .foregroundStyle(Color.red)
                            .monospacedDigit()
                    } else if Date() >= firstStop.dep_time_id || Calendar.current.isDateInToday(firstStop.dep_time_id) {
                        HStack {
                            if lastStopNoIssues.arr_delay != 0 {
                                Text(lastStopNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .strikethrough()
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                            
                            Text(lastStopNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(lastStopNoIssues.arr_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        }
                    } else if Date() >= firstStop.dep_time_id && lastStop.arr_delay == 0 {
                        Text(lastStopNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.green)
                            .monospacedDigit()
                    } else {
                        Text(lastStopNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal).padding(.top, 8)
            
            // delay bar
            if train.issue == "Treno cancellato" {
                ZStack {
                    Text(train.issue)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.red)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
                .cornerRadius(16)
                .padding(8)
            } else if Date() < firstStop.dep_time_id {
                ZStack {
                    let depTime = {
                        if firstStop.dep_time_eff != .distantPast && Calendar.current.isDateInToday(firstStop.dep_time_eff) {
                            return firstStop.dep_time_eff
                        } else {
                            return firstStop.dep_time_id
                        }
                    }()
                    
                    let timeToDeparture = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: depTime)
                    let day = timeToDeparture.day ?? 0
                    let hour = timeToDeparture.hour ?? 0
                    let minute = timeToDeparture.minute ?? 0
                    
                    let timeString: String = {
                        if day > 0 {
                            return String(localized: "Departure on \(depTime.formatted(date: .abbreviated, time: .omitted))")
                        } else if hour > 0 && minute > 0 {
                            return String(localized: "Departure in \(hour)h \(minute)m")
                        } else if hour > 0 && minute == 0 {
                            return String(localized: "Departure in \(hour)h")
                        } else if minute > 0 {
                            return String(localized: "Departure in \(minute)m")
                        } else {
                            return String(localized: "About to depart")
                        }
                    }()
                    
                    Text(timeString)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .padding(.vertical, 8).padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(16)
                .padding(.vertical, 8).padding(.horizontal, 16)
            } else if Date() > lastStop.arr_time_eff {
                HStack (spacing: 8) {
                    ZStack {
                        Text("Arrived on \(lastStopNoIssues.arr_time_eff.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .padding(.vertical, 8).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
                    .padding(.leading)
                    .padding(.vertical, 8)
                    .padding(.trailing, train.issue != "Treno cancellato" ? CGFloat(0) : CGFloat(16))
                    
                    if train.issue != "Treno cancellato" {
                        ZStack {
                            let delayString: String = {
                                if lastStopNoIssues.arr_delay < 0 {
                                    let delay = abs(lastStopNoIssues.arr_delay)
                                    if delay >= 60 {
                                        let hours = delay / 60
                                        let minutes = delay % 60
                                        return "\(hours)h \(minutes)m"
                                    }
                                    return "\(delay)m"
                                } else if lastStopNoIssues.arr_delay == 0 {
                                    return String(localized: "On time")
                                } else {
                                    if lastStopNoIssues.arr_delay >= 60 {
                                        let hours = lastStopNoIssues.arr_delay / 60
                                        let minutes = lastStopNoIssues.arr_delay % 60
                                        return "\(hours)h \(minutes)m"
                                    }
                                    return "\(lastStopNoIssues.arr_delay)m"
                                }
                            }()
                            
                            Text(delayString)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(lastStopNoIssues.arr_delay > 0 ? .red : .green)
                                .padding(.vertical, 8).padding(.horizontal)
                        }
                        .background(lastStopNoIssues.arr_delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .cornerRadius(16)
                        .padding(.trailing).padding(.vertical, 8)
                    }
                }
            } else {
                ZStack {
                    let delayString: String = {
                        if train.delay < 0 {
                            let delay = abs(train.delay)
                            if delay >= 60 {
                                let hours = delay / 60
                                let minutes = delay % 60
                                return String(localized: "Early of \(hours)h \(minutes)m")
                            }
                            return String(localized: "Early of \(delay)m")
                        } else if train.delay == 0 {
                            return String(localized: "On time")
                        } else {
                            if train.delay >= 60 {
                                let hours = train.delay / 60
                                let minutes = train.delay % 60
                                return String(localized: "Late of \(hours)h \(minutes)m")
                            }
                            return String(localized: "Late of \(train.delay)m")
                        }
                    }()
                    
                    Text(delayString)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(train.delay > 0 ? .red : .green)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(train.delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .cornerRadius(16)
                .padding(.vertical, 8).padding(.horizontal, 16)
            }
            
            // other info
            HStack(spacing: 16) {
                if !train.direction.isEmpty && train.direction != "--" {
                    HStack(spacing: 2) {
                        Image(systemName: "train.side.front.car")
                        Text(train.direction)
                    }
                    .font(.caption)
                    .fontDesign(appFontDesign)
                    .foregroundStyle(Color.secondary)
                }
                
                if let routeDistanceKm, routeDistanceKm != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                        Text("\(routeDistanceKm) km")
                    }
                    .font(.caption)
                    .fontDesign(appFontDesign)
                    .foregroundStyle(Color.secondary)
                }
                
                HStack(spacing: 2) {
                    Image(systemName: "clock.fill")
                    
                    let depTime = {
                        if Date() < firstStopNoIssues.dep_time_id {
                            return firstStopNoIssues.dep_time_id
                        } else {
                            return firstStopNoIssues.dep_time_eff
                        }
                    }()
                    
                    let arrTime = {
                        if Date() < firstStopNoIssues.dep_time_id {
                            return lastStopNoIssues.arr_time_id
                        } else {
                            return lastStopNoIssues.arr_time_eff
                        }
                    }()
                    
                    let minutes = Calendar.current.dateComponents([.minute], from: depTime, to: arrTime).minute ?? 0
                    let hours = Calendar.current.dateComponents([.hour], from: depTime, to: arrTime).hour ?? 0
                    
                    let timeString = {
                        if hours > 0 && minutes % 60 != 0 {
                            return "\(hours)h \(minutes % 60)m"
                        } else if hours > 0 && minutes % 60 == 0 {
                            return "\(hours)h"
                        } else {
                            return "\(minutes)m"
                        }
                    }()
                    
                    Text(timeString)
                        .fontDesign(appFontDesign)
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
            
            // train issue
            if !train.issue.isEmpty && train.issue != "Treno cancellato" {
                HStack {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.title)

                    Text(train.issue)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .fontDesign(appFontDesign)
                .foregroundStyle(Color.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
                .cornerRadius(24)
                .padding()
                .padding(.top, 24)
            }
            
            // stops list
            let displayedStops = filteredStops
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(displayedStops.count) stops")
                        .font(.footnote)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if (stops.filter{ $0.is_selected }).count != stops.count {
                        Text("Show all stops")
                            .font(.footnote)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.secondary)
                        
                        Toggle("", isOn: $showAllStops)
                            .labelsHidden()
                            .tint(Color.accentColor)
                    }
                }
                
                Divider()
                
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayedStops.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(Color.secondary)
                        .fontDesign(appFontDesign)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                LazyVStack {
                    ForEach(displayedStops.indices, id: \.self) { index in
                        let stop = displayedStops[index]
                        let routeIndex = stops.firstIndex { $0 === stop } ?? index
                        
                        HStack(spacing: 8) {
                            /// stop status
                            let stopStatusEmoji: (String, Color) = {
                                if Date() < firstStopNoIssues.dep_time_id {
                                    return ("circle.dashed", Color.blue)
                                    
                                } else if stop.status == 3 || train.issue == "Treno cancellato" {
                                    // stop cancelled
                                    return ("xmark.circle.fill", Color.red)
                                    
                                } else if stop.status == 2 {
                                    // stop unscheduled
                                    if firstStop.dep_time_id < Date() {
                                        if stop.is_completed {
                                            return ("checkmark.circle.fill", Color.orange)
                                        } else {
                                            return ("circle.dashed", Color.orange)
                                        }
                                    } else {
                                        return ("circle.dashed", Color.orange)
                                    }
                                    
                                } else if stop.status == 0 || stop.status == 1 {
                                    // stop regular but not done or regular
                                    if firstStop.dep_time_id < Date() {
                                        if stop.is_completed {
                                            return ("checkmark.circle.fill", Color.blue)
                                        } else {
                                            return ("circle.dashed", Color.blue)
                                        }
                                    } else {
                                        return ("circle.dashed", Color.blue)
                                    }
                                }
                                
                                return ("questionmark.circle.fill", Color.gray)
                            }()
                            
                            Image(systemName: stopStatusEmoji.0)
                                .font(Date() >= firstStopNoIssues.dep_time_id || Calendar.current.isDateInToday(firstStopNoIssues.dep_time_id) ? .system(size: 40) : .largeTitle)
                                .foregroundStyle(stopStatusEmoji.1)
                            
                            /// stop info
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    if (Date() >= firstStopNoIssues.dep_time_id || Calendar.current.isDateInToday(firstStopNoIssues.dep_time_id)) && !stop.weather.isEmpty {
                                        Text(stop.weather)
                                            .font(.caption)
                                            .fontDesign(appFontDesign)
                                            .strikethrough((stop.status == 3 || train.issue == "Treno cancellato") && Date() >= firstStopNoIssues.ref_time)
                                            .foregroundStyle(
                                                Date() < firstStopNoIssues.dep_time_id
                                                ? Color.primary
                                                : (
                                                    stop.status == 3 || train.issue == "Treno cancellato"
                                                    ? Color.red
                                                    : (stop.status == 2 ? Color.orange : Color.primary)
                                                )
                                            )
                                    }
                                    
                                    Text(stop.name)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .minimumScaleFactor(0.5)
                                        .font(.caption)
                                        .fontDesign(appFontDesign)
                                        .strikethrough((stop.status == 3 || train.issue == "Treno cancellato") && Date() >= firstStopNoIssues.ref_time)
                                        .foregroundStyle(
                                            Date() < firstStopNoIssues.dep_time_id
                                            ? Color.primary
                                            : (
                                                stop.status == 3 || train.issue == "Treno cancellato"
                                                ? Color.red
                                                : (stop.status == 2 ? Color.orange : Color.primary)
                                            )
                                        )
                                    
                                    if stop.status == 3 || train.issue == "Treno cancellato" {
                                        HStack(spacing: 2) {
                                            Image(systemName: routeIndex == firstIndex ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                                            Text(routeIndex == firstIndex ? stop.dep_time_id.formatted(.dateTime.hour().minute()) : stop.arr_time_id.formatted(.dateTime.hour().minute()))
                                                .monospacedDigit()
                                        }
                                        .font(.caption2)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Date() >= firstStopNoIssues.dep_time_id ? Color.red : Color.primary)
                                        .strikethrough(Date() >= firstStopNoIssues.dep_time_id)
                                    } else {
                                        HStack(spacing: 8) {
                                            if routeIndex != firstIndex && routeIndex != firstIndexNoIssues {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "arrow.down.right.circle.fill")
                                                    Text(Date() >= firstStopNoIssues.dep_time_id || Calendar.current.isDateInToday(firstStopNoIssues.dep_time_id) ? stop.arr_time_eff.formatted(.dateTime.hour().minute()) : stop.arr_time_id.formatted(.dateTime.hour().minute()))
                                                        .monospacedDigit()
                                                }
                                            }
                                            
                                            if routeIndex != lastIndex && routeIndex != lastIndexNoIssues {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "arrow.up.right.circle.fill")
                                                    Text(Date() >= firstStopNoIssues.dep_time_id || Calendar.current.isDateInToday(firstStopNoIssues.dep_time_id) ? stop.dep_time_eff.formatted(.dateTime.hour().minute()) : stop.dep_time_id.formatted(.dateTime.hour().minute()))
                                                        .monospacedDigit()
                                                }
                                            }
                                        }
                                        .font(.caption2)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Date() < (firstStopNoIssues.dep_time_id) ? Color.primary : stop.status == 2 ? Color.orange : Color.primary)
                                    }
                                }
                                
                                Spacer()
                                
                                if stop.status != 3 && train.issue != "Treno cancellato" {
                                    // MARK: - Delay
                                    if Date() > firstStop.dep_time_id || Calendar.current.isDate(firstStop.dep_time_id, inSameDayAs: Date()) {
                                        
                                        if stop.is_completed && (!stop.is_in_station || Date() >= stop.arr_time_eff) {
                                            let delayType = {
                                                if routeIndex == firstIndex {
                                                    return stop.dep_delay
                                                } else {
                                                    return stop.arr_delay
                                                }
                                            }()
                                            
                                            ZStack {
                                                let delayString = {
                                                    if delayType >= 60 && delayType % 60 == 0 {
                                                        return "\(delayType / 60)h"
                                                    } else if delayType >= 60 && delayType % 60 != 0 {
                                                        return "\(delayType / 60)h \(delayType % 60)m"
                                                    } else {
                                                        return "\(delayType)m"
                                                    }
                                                }()
                                                
                                                Text(delayString)
                                                    .font(.footnote)
                                                    .fontDesign(appFontDesign)
                                                    .foregroundStyle(delayType > 0 ? Color.red : Color.green)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(delayType > 0 ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                            .cornerRadius(16)
                                        } else if stop.is_completed {
                                            ZStack {
                                                Text("At the station")
                                                    .font(.footnote)
                                                    .fontDesign(appFontDesign)
                                                    .foregroundStyle(Color.blue)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(16)
                                        } else {
                                            let time = routeIndex == firstIndex ? stop.dep_time_eff : stop.arr_time_eff
                                            let hours = abs(Calendar.current.dateComponents([.hour, .minute], from: Date(), to: time).hour ?? 0)
                                            let minutes = abs(Calendar.current.dateComponents([.hour, .minute], from: Date(), to: time).minute ?? 0)
                                            
                                            let timeString: String = {
                                                if hours == 0 && minutes == 0 {
                                                    return String(localized: "At the station")
                                                } else if hours > 0 {
                                                    return "\(hours)h \(minutes % 60)m"
                                                } else {
                                                    return "\(minutes)m"
                                                }
                                            }()
                                            
                                            ZStack {
                                                Text(timeString)
                                                    .font(.footnote)
                                                    .fontDesign(appFontDesign)
                                                    .foregroundStyle(Color.blue)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(16)
                                            
                                        }
                                    }
                                    
                                    // MARK: - Platform
                                    if Date() > firstStop.dep_time_id || Calendar.current.isDate(firstStop.dep_time_id, inSameDayAs: Date()) {
                                        HStack(spacing: 4) {
                                            Image(systemName: routeIndex == firstIndex ? "arrow.up.right" : "arrow.down.right")
                                                .padding(.vertical, 8).padding(.leading)
                                            Text(stop.platform)
                                                .padding(.vertical, 8).padding(.trailing)
                                        }
                                        .frame(minWidth: 64)
                                        .font(.footnote)
                                        .fontDesign(appFontDesign)
                                        .fontWeight(.medium)
                                        .background(Color.yellow.opacity(0.5))
                                        .cornerRadius(16)
                                        
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4).padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .scrollIndicators(.hidden)
                .listStyle(.plain)
                }
                
                // status legend
                HStack (spacing: 8) {
                    HStack (spacing: 2) {
                        Image(systemName: "circle.fill")
                        Text("Scheduled")
                    }
                    .foregroundStyle(Color.blue)
                    
                    HStack (spacing: 2) {
                        Image(systemName: "circle.fill")
                        Text("Not scheduled")
                    }
                    .foregroundStyle(Color.orange)
                    
                    HStack (spacing: 2) {
                        Image(systemName: "circle.fill")
                        Text("Cancelled")
                    }
                    .foregroundStyle(Color.red)
                }
                .font(.system(size: 10))
                .fontDesign(appFontDesign)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                
                // a future journey has nothing live to report yet
                if showsLastUpdate {
                    Text("Last update: \(train.last_update_time.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
            }
            .padding()
        }
        .refreshable {
            await updateTrainDetails(fetchWeather: true)
        }
        .toolbar {
            // speed button
            if showSpeed {
                ToolbarItem {
                    SpeedGaugeView()
                }
            }
            
            ToolbarSpacer(.flexible)
            
            // favorite button
            ToolbarItem {
                Button {
                    HapticFeedback.confirm()
                    
                    let stop_names = stops.filter { $0.is_selected }.map { $0.name }
                    
                    let stopRefTimesStrings = stops.filter { $0.is_selected }
                        .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }
                    
                    let identifier = normalizedIdentifier
                    
                    if isFavorite {
                        // remove favorite
                        let favoriteToRemove = matchingFavorites().filter { fav in
                            let favTimesStrings = fav.stop_ref_times.map {
                                $0.formatted(date: .omitted, time: .shortened)
                            }
                            
                            return fav.identifier == identifier &&
                                    fav.stop_names == stop_names &&
                                    favTimesStrings == stopRefTimesStrings
                        }
                        
                        for favorite in favoriteToRemove {
                            modelContext.delete(favorite)
                        }
                        isFavorite = false
                    } else {
                        // add favorite
                        let stop_ref_times = stops.filter { $0.is_selected }.map { $0.ref_time }
                        
                        let favoriteToAdd = Favorite(
                            id: UUID(),
                            index: 0,
                            identifier: identifier,
                            provider: train.provider,
                            logo: train.logo,
                            number: train.number,
                            stop_names: stop_names,
                            stop_ref_times: stop_ref_times
                        )
                        modelContext.insert(favoriteToAdd)
                        isFavorite = true
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }
                .tint(isFavorite ? Color.red : Color.primary)
            }

            ToolbarSpacer(.flexible)

            // add seat button
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticFeedback.confirm()
                    seatsSheet = true
                } label: {
                    HStack {
                        Image(systemName: "figure.seated.seatbelt")
                            .fontWeight(.semibold)

                        let textString = {
                            if let firstUser = seats.first {
                                let carriage = firstUser.carriage
                                let number = firstUser.number
                                if !carriage.isEmpty && !number.isEmpty {
                                    return "\(carriage)-\(number)"
                                } else {
                                    return "\(firstUser.name)"
                                }
                            }
                            return String(localized: "Add")
                        }()

                        Text(textString)
                    }
                    .fontDesign(appFontDesign)
                    .foregroundStyle(Color.primary)
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                if let shareURL = TrainSharing.url(train: train, stops: stops, seats: seats) {
                    // the bare link, with no title alongside it
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                    }
                    .simultaneousGesture(TapGesture().onEnded { HapticFeedback.tap() })
                }
            }

            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        .searchable(text: $searchText, prompt: "Search stops")
        .sheet(isPresented: $seatsSheet) {
            SeatsView(train: train, seats: seats, initialSeatID: pendingSeatID)
                .presentationDetents([.large])
        }
        .background(appBackgroundColor)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)

            if showTicketInitially {
                pendingSeatID = ticketSeatID
                seatsSheet = true
                showTicketInitially = false
                ticketSeatID = nil
            }
        }
        .task(id: train.id) {
            refreshDerivedState()
            guard !Task.isCancelled else { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await updateTrainDetails(fetchWeather: false)
        }
        .onChange(of: stops.count) { _, _ in
            stopSummary = StopSummary.calculate(in: stops)
            routeDistanceKm = distanceBetweenStations(from: summary.first.name, to: summary.last.name)
            isFavorite = computeIsFavorite()
        }
        .onChange(of: showAllStops) { _, _ in
            stopSummary = StopSummary.calculate(in: stops)
        }
        .onChange(of: showTicketInitially) { _, newValue in
            if newValue {
                pendingSeatID = ticketSeatID
                if !seatsSheet {
                    seatsSheet = true
                }
                showTicketInitially = false
                ticketSeatID = nil
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func refreshDerivedState() {
        stopSummary = StopSummary.calculate(in: stops)
        isFavorite = computeIsFavorite()
        routeDistanceKm = distanceBetweenStations(from: summary.first.name, to: summary.last.name)
    }

    private func matchingFavorites() -> [Favorite] {
        let identifier = normalizedIdentifier
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.identifier == identifier })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func computeIsFavorite() -> Bool {
        let stop_names = stops.filter { $0.is_selected }.map { $0.name }
        let stop_ref_times = stops.filter { $0.is_selected }
            .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }

        return matchingFavorites().contains { fav in
            guard fav.stop_names == stop_names else { return false }
            let favRefTimes = fav.stop_ref_times.map {
                $0.formatted(date: .omitted, time: .shortened)
            }
            return favRefTimes == stop_ref_times
        }
    }

    @MainActor
    private func updateTrainDetails(fetchWeather: Bool = false) async {
        guard !isRefreshing else { return }

        let firstStop_refTime = stops
            .sorted(by: { $0.ref_time < $1.ref_time })
            .first?.ref_time ?? .distantPast

        guard Calendar.current.isDateInToday(firstStop_refTime) else { return }

        if !fetchWeather, Date().timeIntervalSince(train.last_update_time) < 25 {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let todayStops = stops

        /// fetch new data
        let results: [String:Any] = await {
            switch train.provider {
                case "trenitalia":
                    return await TrenitaliaAPI().info(identifier: train.identifier, shouldFetchWeather: fetchWeather) ?? [:]
                case "italo":
                    return await ItaloAPI().info(identifier: train.identifier, shouldFetchWeather: fetchWeather) ?? [:]
                default:
                    return [:]
            }
        }()
        guard !results.isEmpty else { return }

        /// update train data, only writing values that actually changed so
        /// unchanged refreshes don't dirty the context and re-render observers
        var trainChanged = false
        let newDelay = results["delay"] as? Int ?? 0
        let newDirection = results["direction"] as? String ?? ""
        let newIssue = results["issue"] as? String ?? ""
        if train.delay != newDelay { train.delay = newDelay; trainChanged = true }
        if train.direction != newDirection { train.direction = newDirection; trainChanged = true }
        if train.issue != newIssue { train.issue = newIssue; trainChanged = true }

        /// update stops data
        var stopsChanged = false
        let stopsUpdated = results["stops"] as? [[String:Any]] ?? []
        for stop in todayStops {
            /// get the stop updated whose name correspond to the today stops
            guard let stopUpdated = stopsUpdated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }

            let newPlatform = stopUpdated["platform"] as? String ?? ""
            let newWeather = stopUpdated["weather"] as? String ?? ""
            let newStatus = stopUpdated["status"] as? Int ?? 0
            let newCompleted = stopUpdated["is_completed"] as? Bool ?? false
            let newInStation = stopUpdated["is_in_station"] as? Bool ?? false
            let newDepDelay = stopUpdated["dep_delay"] as? Int ?? 0
            let newArrDelay = stopUpdated["arr_delay"] as? Int ?? 0
            let newDepEff = stopUpdated["dep_time_eff"] as? Date ?? .distantPast
            let newArrEff = stopUpdated["arr_time_eff"] as? Date ?? .distantPast

            if stop.platform != newPlatform { stop.platform = newPlatform; stopsChanged = true }
            if !newWeather.isEmpty && stop.weather != newWeather { stop.weather = newWeather; stopsChanged = true }
            if stop.status != newStatus { stop.status = newStatus; stopsChanged = true }
            if stop.is_completed != newCompleted { stop.is_completed = newCompleted; stopsChanged = true }
            if stop.is_in_station != newInStation { stop.is_in_station = newInStation; stopsChanged = true }
            if stop.dep_delay != newDepDelay { stop.dep_delay = newDepDelay; stopsChanged = true }
            if stop.arr_delay != newArrDelay { stop.arr_delay = newArrDelay; stopsChanged = true }
            if stop.dep_time_eff != newDepEff { stop.dep_time_eff = newDepEff; stopsChanged = true }
            if stop.arr_time_eff != newArrEff { stop.arr_time_eff = newArrEff; stopsChanged = true }
        }

        guard trainChanged || stopsChanged else { return }

        train.last_update_time = results["last_update_time"] as? Date ?? .distantPast

        stopSummary = StopSummary.calculate(in: stops)

        // update calendar event if exists
        if train.calendarEventIdentifier != nil,
           let settings = profiles.primary?.calendarSettings {
            await CalendarManager.shared.syncTrainEvent(
                train: train,
                stops: todayStops,
                seats: seats,
                titleFormat: settings.titleFormat,
                calendarIdentifier: settings.calendarIdentifier,
                travelTime: settings.travelTime
            )
        }
        
        try? modelContext.save()
        if fetchWeather {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private func detailsPreview(train: Train, stops: [Stop], seats: [Seat] = []) -> some View {
    let container: ModelContainer = {
        let schema = Schema([Train.self, Stop.self, Seat.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }()
    let context = ModelContext(container)
    context.insert(train)
    stops.forEach { context.insert($0) }
    seats.forEach { context.insert($0) }
    try? context.save()

    return NavigationStack {
        DetailsView(train: train, showTicketInitially: .constant(false), ticketSeatID: .constant(nil))
            .modelContainer(container)
    }
}

#Preview {
    let trainId = UUID()
    let now = Date()
    
    let mockTrain = Train(
        id: trainId,
        logo: "FR",
        number: "9612",
        identifier: "TS/9612/123456",
        provider: "trenitalia",
        last_update_time: now,
        delay: 50,
        direction: "Salerno",
        issue: ""
    )
    
    let mockStops = [
        Stop(id: trainId, name: "Torino Porta Nuova", platform: "3", weather: "☀️ 2°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now, arr_time_id: now, dep_time_eff: now, arr_time_eff: now, ref_time: now),
        Stop(id: trainId, name: "Torino Porta Susa", platform: "1", weather: "☀️ 2°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 2, arr_delay: 1, dep_time_id: now.addingTimeInterval(600), arr_time_id: now.addingTimeInterval(600), dep_time_eff: now.addingTimeInterval(720), arr_time_eff: now.addingTimeInterval(660), ref_time: now.addingTimeInterval(600)),
        Stop(id: trainId, name: "Vercelli", platform: "2", weather: "🌫️ 0°C", is_selected: false, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(1800), arr_time_id: now.addingTimeInterval(1800), dep_time_eff: now.addingTimeInterval(1800), arr_time_eff: now.addingTimeInterval(1800), ref_time: now.addingTimeInterval(1800)),
        Stop(id: trainId, name: "Novara", platform: "3", weather: "🌫️ 0°C", is_selected: false, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(2400), arr_time_id: now.addingTimeInterval(2400), dep_time_eff: now.addingTimeInterval(2400), arr_time_eff: now.addingTimeInterval(2400), ref_time: now.addingTimeInterval(2400)),
        Stop(id: trainId, name: "Milano Centrale", platform: "14", weather: "⛅️ 1°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 5, arr_delay: 4, dep_time_id: now.addingTimeInterval(3600), arr_time_id: now.addingTimeInterval(3600), dep_time_eff: now.addingTimeInterval(3900), arr_time_eff: now.addingTimeInterval(3840), ref_time: now.addingTimeInterval(3600)),
        Stop(id: trainId, name: "Milano Rogoredo", platform: "6", weather: "⛅️ 1°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(4500), arr_time_id: now.addingTimeInterval(4500), dep_time_eff: now.addingTimeInterval(4500), arr_time_eff: now.addingTimeInterval(4500), ref_time: now.addingTimeInterval(4500)),
        Stop(id: trainId, name: "Reggio Emilia AV", platform: "1", weather: "☁️ 3°C", is_selected: false, status: 3, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(6600), arr_time_id: now.addingTimeInterval(6600), dep_time_eff: now.addingTimeInterval(6600), arr_time_eff: now.addingTimeInterval(6600), ref_time: now.addingTimeInterval(6600)),
        Stop(id: trainId, name: "Bologna Centrale", platform: "17", weather: "🌧️ 4°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(8400), arr_time_id: now.addingTimeInterval(8400), dep_time_eff: now.addingTimeInterval(8400), arr_time_eff: now.addingTimeInterval(8400), ref_time: now.addingTimeInterval(8400)),
        Stop(id: trainId, name: "Firenze S.M.N.", platform: "9", weather: "🌧️ 6°C", is_selected: true, status: 2, is_completed: false, is_in_station: false, dep_delay: 10, arr_delay: 8, dep_time_id: now.addingTimeInterval(12000), arr_time_id: now.addingTimeInterval(12000), dep_time_eff: now.addingTimeInterval(12600), arr_time_eff: now.addingTimeInterval(12480), ref_time: now.addingTimeInterval(12000)),
        Stop(id: trainId, name: "Roma Tiburtina", platform: "13", weather: "☁️ 9°C", is_selected: false, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(17400), arr_time_id: now.addingTimeInterval(17400), dep_time_eff: now.addingTimeInterval(17400), arr_time_eff: now.addingTimeInterval(17400), ref_time: now.addingTimeInterval(17400)),
        Stop(id: trainId, name: "Roma Termini", platform: "1", weather: "🌧️ 10°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(18000), arr_time_id: now.addingTimeInterval(18000), dep_time_eff: now.addingTimeInterval(18000), arr_time_eff: now.addingTimeInterval(18000), ref_time: now.addingTimeInterval(18000)),
        Stop(id: trainId, name: "Napoli Centrale", platform: "20", weather: "☀️ 12°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(21600), arr_time_id: now.addingTimeInterval(21600), dep_time_eff: now.addingTimeInterval(21600), arr_time_eff: now.addingTimeInterval(21600), ref_time: now.addingTimeInterval(21600))
    ]
    
    let mockSeats = [
        Seat(id: UUID(), trainID: trainId, name: "Marco", carriage: "5", number: "12A")
    ]

    detailsPreview(train: mockTrain, stops: mockStops, seats: mockSeats)
}

#Preview("Issue") {
    let trainId = UUID()
    let now = Date()
    
    let mockTrain = Train(
        id: trainId,
        logo: "FR",
        number: "9612",
        identifier: "TS/9612/123456",
        provider: "trenitalia",
        last_update_time: now,
        delay: 0,
        direction: "Salerno",
        issue: "Treno cancellato"
    )
    
    let mockStops = [
        Stop(id: trainId, name: "Torino Porta Nuova", platform: "3", weather: "☀️ 2°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now, arr_time_id: now, dep_time_eff: now, arr_time_eff: now, ref_time: now),
        Stop(id: trainId, name: "Milano Centrale", platform: "14", weather: "⛅️ 1°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(3600), arr_time_id: now.addingTimeInterval(3600), dep_time_eff: now.addingTimeInterval(3600), arr_time_eff: now.addingTimeInterval(3600), ref_time: now.addingTimeInterval(3600)),
        Stop(id: trainId, name: "Bologna Centrale", platform: "17", weather: "🌧️ 4°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(8400), arr_time_id: now.addingTimeInterval(8400), dep_time_eff: now.addingTimeInterval(8400), arr_time_eff: now.addingTimeInterval(8400), ref_time: now.addingTimeInterval(8400)),
        Stop(id: trainId, name: "Roma Termini", platform: "1", weather: "🌧️ 10°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(18000), arr_time_id: now.addingTimeInterval(18000), dep_time_eff: now.addingTimeInterval(18000), arr_time_eff: now.addingTimeInterval(18000), ref_time: now.addingTimeInterval(18000))
    ]

    detailsPreview(train: mockTrain, stops: mockStops)
}

#Preview("Generic Issue") {
    let trainId = UUID()
    let now = Date()
    
    let mockTrain = Train(
        id: trainId,
        logo: "FR",
        number: "9612",
        identifier: "TS/9612/123456",
        provider: "trenitalia",
        last_update_time: now,
        delay: 0,
        direction: "Salerno",
        issue: "Circolazione rallentata per guasto tecnico"
    )
    
    let mockStops = [
        Stop(id: trainId, name: "Torino Porta Nuova", platform: "3", weather: "☀️ 2°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now, arr_time_id: now, dep_time_eff: now, arr_time_eff: now, ref_time: now),
        Stop(id: trainId, name: "Milano Centrale", platform: "14", weather: "⛅️ 1°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(3600), arr_time_id: now.addingTimeInterval(3600), dep_time_eff: now.addingTimeInterval(3600), arr_time_eff: now.addingTimeInterval(3600), ref_time: now.addingTimeInterval(3600)),
        Stop(id: trainId, name: "Bologna Centrale", platform: "17", weather: "🌧️ 4°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(8400), arr_time_id: now.addingTimeInterval(8400), dep_time_eff: now.addingTimeInterval(8400), arr_time_eff: now.addingTimeInterval(8400), ref_time: now.addingTimeInterval(8400)),
        Stop(id: trainId, name: "Roma Termini", platform: "1", weather: "🌧️ 10°C", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: now.addingTimeInterval(18000), arr_time_id: now.addingTimeInterval(18000), dep_time_eff: now.addingTimeInterval(18000), arr_time_eff: now.addingTimeInterval(18000), ref_time: now.addingTimeInterval(18000))
    ]

    detailsPreview(train: mockTrain, stops: mockStops)
}
