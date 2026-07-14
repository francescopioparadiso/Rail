import SwiftUI
import SwiftData
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import WidgetKit
import StoreKit

// MARK: - Enums

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct DetailsView: View {
    // MARK: - Properties
    // enviroment variables
    @Environment(\.colorScheme) var color_scheme
    @Environment(\.requestReview) var request_review
    @Environment(\.modelContext) private var model_context
    @Query private var profiles: [UserProfile]
    
    // data variables
    let train: Train
    @Query private var stops: [Stop]
    @Query private var seats: [Seat]
    @Binding var show_ticket_initially: Bool
    @Binding var ticketSeatID: UUID?
    
    // state variables
    @State private var seats_sheet: Bool = false
    @State private var pendingSeatID: UUID?
    @State private var show_all_stops: Bool = false
    @State private var searchText = ""
    @State private var route_distance_km: Int?
    @State private var is_favorite: Bool = false
    @State private var is_refreshing = false
    @State private var stop_summary: StopSummary
    
    init(
        train: Train,
        show_ticket_initially: Binding<Bool>,
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
        self._show_ticket_initially = show_ticket_initially
        self._ticketSeatID = ticketSeatID
        self._stop_summary = State(initialValue: StopSummary.calculate(in: []))
    }

    // MARK: - Computed Properties
    private var summary: StopSummary { stop_summary }

    private var base_stops: [Stop] {
        show_all_stops ? stops : stops.filter { $0.is_selected }
    }

    private var filtered_stops: [Stop] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base_stops }
        return base_stops.filter { $0.name.lowercased().contains(query) }
    }

    private var show_speed: Bool {
        return Date() <= summary.last.arr_time_eff || Calendar.current.isDateInToday(summary.last.arr_time_eff)
    }
    
    private var first_stop: Stop {
        show_all_stops ?
        stops.first ?? Stop.placeholder() :
        summary.first
    }
    private var last_stop: Stop {
        show_all_stops ?
        stops.last ?? Stop.placeholder() :
        summary.last
    }
    private var first_stop_no_issues: Stop {
        show_all_stops ?
        stops.first(where: { $0.status != 3 }) ?? stops.first ?? Stop.placeholder() :
        summary.firstNoIssues
    }
    private var last_stop_no_issues: Stop {
        show_all_stops ?
        stops.last(where: { $0.status != 3 }) ?? stops.last ?? Stop.placeholder() :
        summary.lastNoIssues
    }
    
    private var first_index: Int {
        stops.startIndex
    }
    private var last_index: Int {
        stops.endIndex
    }
    private var first_index_no_issues: Int {
        stops.firstIndex(where: { $0.status != 3 }) ?? (stops.indices.first ?? 0)
    }
    private var last_index_no_issues: Int {
        stops.lastIndex(where: { $0.status != 3 }) ?? (stops.indices.last ?? 0)
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
                    .fontDesign(app_font_design)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.primary)
                
                Spacer()
            }
            .padding(.horizontal).padding(.top)
            
            // departure and arrival
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(first_stop_no_issues.name)
                        .font(.subheadline)
                        .fontDesign(app_font_design)
                        .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                        .strikethrough(train.issue == "Treno cancellato")
                    
                    Spacer()
                    
                    if train.issue == "Treno cancellato" {
                        Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .strikethrough()
                            .foregroundStyle(Color.red)
                            .monospacedDigit()
                    } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                        HStack {
                            if first_stop_no_issues.dep_delay != 0 {
                                Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .strikethrough()
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                            
                            Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(first_stop_no_issues.dep_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        }
                    } else {
                        Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .foregroundStyle(Date() >= first_stop_no_issues.dep_time_id && first_stop_no_issues.dep_delay == 0 ? Color.green : Color.primary)
                            .monospacedDigit()
                    }
                }
                
                HStack {
                    Text(last_stop_no_issues.name)
                        .font(.subheadline)
                        .fontDesign(app_font_design)
                        .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                        .strikethrough(train.issue == "Treno cancellato")
                    
                    Spacer()
                    
                    if train.issue == "Treno cancellato" {
                        Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .strikethrough()
                            .foregroundStyle(Color.red)
                            .monospacedDigit()
                    } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                        HStack {
                            if last_stop_no_issues.arr_delay != 0 {
                                Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .strikethrough()
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                            }
                            
                            Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        }
                    } else if Date() >= first_stop.dep_time_id && last_stop.arr_delay == 0 {
                        Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .foregroundStyle(Color.green)
                            .monospacedDigit()
                    } else {
                        Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                            .fontDesign(app_font_design)
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
                        .fontDesign(app_font_design)
                        .foregroundStyle(Color.red)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
                .cornerRadius(16)
                .padding(8)
            } else if Date() < first_stop.dep_time_id {
                ZStack {
                    let dep_time = {
                        if first_stop.dep_time_eff != .distantPast && Calendar.current.isDateInToday(first_stop.dep_time_eff) {
                            return first_stop.dep_time_eff
                        } else {
                            return first_stop.dep_time_id
                        }
                    }()
                    
                    let time_to_departure = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: dep_time)
                    let day = time_to_departure.day ?? 0
                    let hour = time_to_departure.hour ?? 0
                    let minute = time_to_departure.minute ?? 0
                    
                    let time_string: String = {
                        if day > 0 {
                            return String(localized: "Departure on \(dep_time.formatted(date: .abbreviated, time: .omitted))")
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
                    
                    Text(time_string)
                        .font(.subheadline)
                        .fontDesign(app_font_design)
                        .padding(.vertical, 8).padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(16)
                .padding(.vertical, 8).padding(.horizontal, 16)
            } else if Date() > last_stop.arr_time_eff {
                HStack (spacing: 8) {
                    ZStack {
                        Text("Arrived on \(last_stop_no_issues.arr_time_eff.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .fontDesign(app_font_design)
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
                            let delay_string: String = {
                                if last_stop_no_issues.arr_delay < 0 {
                                    let delay = abs(last_stop_no_issues.arr_delay)
                                    if delay >= 60 {
                                        let hours = delay / 60
                                        let minutes = delay % 60
                                        return "\(hours)h \(minutes)m"
                                    }
                                    return "\(delay)m"
                                } else if last_stop_no_issues.arr_delay == 0 {
                                    return String(localized: "On time")
                                } else {
                                    if last_stop_no_issues.arr_delay >= 60 {
                                        let hours = last_stop_no_issues.arr_delay / 60
                                        let minutes = last_stop_no_issues.arr_delay % 60
                                        return "\(hours)h \(minutes)m"
                                    }
                                    return "\(last_stop_no_issues.arr_delay)m"
                                }
                            }()
                            
                            Text(delay_string)
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? .red : .green)
                                .padding(.vertical, 8).padding(.horizontal)
                        }
                        .background(last_stop_no_issues.arr_delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .cornerRadius(16)
                        .padding(.trailing).padding(.vertical, 8)
                    }
                }
            } else {
                ZStack {
                    let delay_string: String = {
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
                    
                    Text(delay_string)
                        .font(.subheadline)
                        .fontDesign(app_font_design)
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
                    .fontDesign(app_font_design)
                    .foregroundStyle(Color.secondary)
                }
                
                if let route_distance_km, route_distance_km != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                        Text("\(route_distance_km) km")
                    }
                    .font(.caption)
                    .fontDesign(app_font_design)
                    .foregroundStyle(Color.secondary)
                }
                
                HStack(spacing: 2) {
                    Image(systemName: "clock.fill")
                    
                    let dep_time = {
                        if Date() < first_stop_no_issues.dep_time_id {
                            return first_stop_no_issues.dep_time_id
                        } else {
                            return first_stop_no_issues.dep_time_eff
                        }
                    }()
                    
                    let arr_time = {
                        if Date() < first_stop_no_issues.dep_time_id {
                            return last_stop_no_issues.arr_time_id
                        } else {
                            return last_stop_no_issues.arr_time_eff
                        }
                    }()
                    
                    let minutes = Calendar.current.dateComponents([.minute], from: dep_time, to: arr_time).minute ?? 0
                    let hours = Calendar.current.dateComponents([.hour], from: dep_time, to: arr_time).hour ?? 0
                    
                    let time_string = {
                        if hours > 0 && minutes % 60 != 0 {
                            return "\(hours)h \(minutes % 60)m"
                        } else if hours > 0 && minutes % 60 == 0 {
                            return "\(hours)h"
                        } else {
                            return "\(minutes)m"
                        }
                    }()
                    
                    Text(time_string)
                        .fontDesign(app_font_design)
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
                .fontDesign(app_font_design)
                .foregroundStyle(Color.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
                .cornerRadius(24)
                .padding()
                .padding(.top, 24)
            }
            
            // stops list
            let displayed_stops = filtered_stops
            let non_cancelled_count = displayed_stops.count(where: { $0.status != 3 })
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(displayed_stops.count) stops")
                        .font(.footnote)
                        .fontDesign(app_font_design)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if (stops.filter{ $0.is_selected }).count != stops.count {
                        Text("Show all stops")
                            .font(.footnote)
                            .fontDesign(app_font_design)
                            .foregroundStyle(Color.secondary)
                        
                        Toggle("", isOn: $show_all_stops)
                            .labelsHidden()
                            .tint(Color.accentColor)
                    }
                }
                
                Divider()
                
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayed_stops.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .fontDesign(app_font_design)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                LazyVStack {
                    ForEach(displayed_stops.indices, id: \.self) { index in
                        let stop = displayed_stops[index]
                        
                        HStack(spacing: 8) {
                            /// stop status
                            let stop_status_emoji: (String, Color) = {
                                if Date() < first_stop_no_issues.dep_time_id {
                                    return ("circle.dashed", Color.blue)
                                    
                                } else if stop.status == 3 || train.issue == "Treno cancellato" {
                                    // stop cancelled
                                    return ("xmark.circle.fill", Color.red)
                                    
                                } else if stop.status == 2 {
                                    // stop unscheduled
                                    if first_stop.dep_time_id < Date() {
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
                                    if first_stop.dep_time_id < Date() {
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
                            
                            Image(systemName: stop_status_emoji.0)
                                .font(Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) ? .system(size: 40) : .largeTitle)
                                .foregroundStyle(stop_status_emoji.1)
                            
                            /// stop info
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    if (Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id)) && !stop.weather.isEmpty {
                                        Text(stop.weather)
                                            .font(.caption)
                                            .fontDesign(app_font_design)
                                            .strikethrough((stop.status == 3 || train.issue == "Treno cancellato") && Date() >= first_stop_no_issues.ref_time)
                                            .foregroundStyle(
                                                Date() < first_stop_no_issues.dep_time_id
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
                                        .fontDesign(app_font_design)
                                        .strikethrough((stop.status == 3 || train.issue == "Treno cancellato") && Date() >= first_stop_no_issues.ref_time)
                                        .foregroundStyle(
                                            Date() < first_stop_no_issues.dep_time_id
                                            ? Color.primary
                                            : (
                                                stop.status == 3 || train.issue == "Treno cancellato"
                                                ? Color.red
                                                : (stop.status == 2 ? Color.orange : Color.primary)
                                            )
                                        )
                                    
                                    if stop.status == 3 || train.issue == "Treno cancellato" {
                                        HStack(spacing: 2) {
                                            Image(systemName: index == first_index ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                                            Text(index == first_index ? stop.dep_time_id.formatted(.dateTime.hour().minute()) : stop.arr_time_id.formatted(.dateTime.hour().minute()))
                                                .monospacedDigit()
                                        }
                                        .font(.caption2)
                                        .fontDesign(app_font_design)
                                        .foregroundStyle(Date() >= first_stop_no_issues.dep_time_id ? Color.red : Color.primary)
                                        .strikethrough(Date() >= first_stop_no_issues.dep_time_id)
                                    } else {
                                        HStack(spacing: 8) {
                                            if index != first_index && index != first_index_no_issues {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "arrow.down.right.circle.fill")
                                                    Text(Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) ? stop.arr_time_eff.formatted(.dateTime.hour().minute()) : stop.arr_time_id.formatted(.dateTime.hour().minute()))
                                                        .monospacedDigit()
                                                }
                                            }
                                            
                                            if index != last_index && index != last_index_no_issues && index != non_cancelled_count - 1 {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "arrow.up.right.circle.fill")
                                                    Text(Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) ? stop.dep_time_eff.formatted(.dateTime.hour().minute()) : stop.dep_time_id.formatted(.dateTime.hour().minute()))
                                                        .monospacedDigit()
                                                }
                                            }
                                        }
                                        .font(.caption2)
                                        .fontDesign(app_font_design)
                                        .foregroundStyle(Date() < (first_stop_no_issues.dep_time_id) ? Color.primary : stop.status == 2 ? Color.orange : Color.primary)
                                    }
                                }
                                
                                Spacer()
                                
                                if stop.status != 3 && train.issue != "Treno cancellato" {
                                    // MARK: - Delay
                                    if Date() > first_stop.dep_time_id || Calendar.current.isDate(first_stop.dep_time_id, inSameDayAs: Date()) {
                                        
                                        if stop.is_completed && (!stop.is_in_station || Date() >= stop.arr_time_eff) {
                                            let delay_type = {
                                                if index == first_index {
                                                    return stop.dep_delay
                                                } else {
                                                    return stop.arr_delay
                                                }
                                            }()
                                            
                                            ZStack {
                                                let delay_string = {
                                                    if delay_type >= 60 && delay_type % 60 == 0 {
                                                        return "\(delay_type / 60)h"
                                                    } else if delay_type >= 60 && delay_type % 60 != 0 {
                                                        return "\(delay_type / 60)h \(delay_type % 60)m"
                                                    } else {
                                                        return "\(delay_type)m"
                                                    }
                                                }()
                                                
                                                Text(delay_string)
                                                    .font(.footnote)
                                                    .fontDesign(app_font_design)
                                                    .foregroundStyle(delay_type > 0 ? Color.red : Color.green)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(delay_type > 0 ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                            .cornerRadius(16)
                                        } else if stop.is_completed {
                                            ZStack {
                                                Text("At the station")
                                                    .font(.footnote)
                                                    .fontDesign(app_font_design)
                                                    .foregroundStyle(Color.blue)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(16)
                                        } else {
                                            let time = index == 0 ? stop.dep_time_eff : stop.arr_time_eff
                                            let hours = abs(Calendar.current.dateComponents([.hour, .minute], from: Date(), to: time).hour ?? 0)
                                            let minutes = abs(Calendar.current.dateComponents([.hour, .minute], from: Date(), to: time).minute ?? 0)
                                            
                                            let time_string: String = {
                                                if hours == 0 && minutes == 0 {
                                                    return String(localized: "At the station")
                                                } else if hours > 0 {
                                                    return "\(hours)h \(minutes % 60)m"
                                                } else {
                                                    return "\(minutes)m"
                                                }
                                            }()
                                            
                                            ZStack {
                                                Text(time_string)
                                                    .font(.footnote)
                                                    .fontDesign(app_font_design)
                                                    .foregroundStyle(Color.blue)
                                                    .padding(.vertical, 8).padding(.horizontal)
                                            }
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(16)
                                            
                                        }
                                    }
                                    
                                    // MARK: - Platform
                                    if Date() > first_stop.dep_time_id || Calendar.current.isDate(first_stop.dep_time_id, inSameDayAs: Date()) {
                                        HStack(spacing: 4) {
                                            Image(systemName: index == 0 ? "arrow.up.right" : "arrow.down.right")
                                                .padding(.vertical, 8).padding(.leading)
                                            Text(stop.platform)
                                                .padding(.vertical, 8).padding(.trailing)
                                        }
                                        .frame(minWidth: 64)
                                        .font(.footnote)
                                        .fontDesign(app_font_design)
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
                .fontDesign(app_font_design)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                
                // last updated time
                Text("Last udpate: \(train.last_update_time.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .fontDesign(app_font_design)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
            .padding()
        }
        .refreshable {
            await update_train_details(fetchWeather: true)
        }
        .toolbar {
            // speed button
            if show_speed {
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
                    
                    let stop_ref_times_strings = stops.filter { $0.is_selected }
                        .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }
                    
                    let identifier = normalized_identifier
                    
                    if is_favorite {
                        // remove favorite
                        let favorite_to_remove = matching_favorites().filter { fav in
                            let fav_times_strings = fav.stop_ref_times.map {
                                $0.formatted(date: .omitted, time: .shortened)
                            }
                            
                            return fav.identifier == identifier &&
                                    fav.stop_names == stop_names &&
                                    fav_times_strings == stop_ref_times_strings
                        }
                        
                        for favorite in favorite_to_remove {
                            model_context.delete(favorite)
                        }
                        is_favorite = false
                    } else {
                        // add favorite
                        let stop_ref_times = stops.filter { $0.is_selected }.map { $0.ref_time }
                        
                        let favorite_to_add = Favorite(
                            id: UUID(),
                            index: 0,
                            identifier: identifier,
                            provider: train.provider,
                            logo: train.logo,
                            number: train.number,
                            stop_names: stop_names,
                            stop_ref_times: stop_ref_times
                        )
                        model_context.insert(favorite_to_add)
                        is_favorite = true
                    }
                } label: {
                    Image(systemName: is_favorite ? "heart.fill" : "heart")
                }
                .tint(is_favorite ? Color.red : Color.primary)
            }

            ToolbarSpacer(.flexible)

            // add seat button
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticFeedback.confirm()
                    seats_sheet = true
                } label: {
                    HStack {
                        Image(systemName: "figure.seated.seatbelt")
                            .fontWeight(.semibold)

                        let text_string = {
                            if let first_user = seats.first {
                                let carriage = first_user.carriage
                                let number = first_user.number
                                if !carriage.isEmpty && !number.isEmpty {
                                    return "\(carriage)-\(number)"
                                } else {
                                    return "\(first_user.name)"
                                }
                            }
                            return String(localized: "Add")
                        }()

                        Text(text_string)
                    }
                    .fontDesign(app_font_design)
                    .foregroundStyle(Color.primary)
                }
            }

            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        .searchable(text: $searchText, prompt: "Search stops")
        .sheet(isPresented: $seats_sheet) {
            SeatsView(train: train, seats: seats, initialSeatID: pendingSeatID)
                .presentationDetents([.large])
        }
        .background(app_background_color)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: request_review)

            if show_ticket_initially {
                pendingSeatID = ticketSeatID
                seats_sheet = true
                show_ticket_initially = false
                ticketSeatID = nil
            }
        }
        .task(id: train.id) {
            refreshDerivedState()
            guard !Task.isCancelled else { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await update_train_details(fetchWeather: false)
        }
        .onChange(of: stops.count) { _, _ in
            stop_summary = StopSummary.calculate(in: stops)
            route_distance_km = distance_between_stations(from: summary.first.name, to: summary.last.name)
            is_favorite = compute_is_favorite()
        }
        .onChange(of: show_all_stops) { _, _ in
            stop_summary = StopSummary.calculate(in: stops)
        }
        .onChange(of: show_ticket_initially) { _, newValue in
            if newValue {
                pendingSeatID = ticketSeatID
                if !seats_sheet {
                    seats_sheet = true
                }
                show_ticket_initially = false
                ticketSeatID = nil
            }
        }
    }
    
    // MARK: - Functions
    @MainActor
    private func refreshDerivedState() {
        stop_summary = StopSummary.calculate(in: stops)
        is_favorite = compute_is_favorite()
        route_distance_km = distance_between_stations(from: summary.first.name, to: summary.last.name)
    }

    private var normalized_identifier: String {
        train.identifier.contains("/") ?
            String(train.identifier.split(separator: "/").dropLast().joined(separator: "/")) :
            train.identifier
    }

    private func matching_favorites() -> [Favorite] {
        let identifier = normalized_identifier
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.identifier == identifier })
        return (try? model_context.fetch(descriptor)) ?? []
    }

    private func compute_is_favorite() -> Bool {
        let stop_names = stops.filter { $0.is_selected }.map { $0.name }
        let stop_ref_times = stops.filter { $0.is_selected }
            .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }

        return matching_favorites().contains { fav in
            guard fav.stop_names == stop_names else { return false }
            let fav_ref_times = fav.stop_ref_times.map {
                $0.formatted(date: .omitted, time: .shortened)
            }
            return fav_ref_times == stop_ref_times
        }
    }

    @MainActor
    private func update_train_details(fetchWeather: Bool = false) async {
        guard !is_refreshing else { return }

        let firstStop_refTime = stops
            .sorted(by: { $0.ref_time < $1.ref_time })
            .first?.ref_time ?? .distantPast

        guard Calendar.current.isDateInToday(firstStop_refTime) else { return }

        if !fetchWeather, Date().timeIntervalSince(train.last_update_time) < 25 {
            return
        }

        is_refreshing = true
        defer { is_refreshing = false }

        let today_stops = stops

        /// fetch new data
        let results: [String:Any] = await {
            switch train.provider {
                case "trenitalia":
                    return await TrenitaliaAPI().info(identifier: train.identifier, should_fetch_weather: fetchWeather) ?? [:]
                case "italo":
                    return await ItaloAPI().info(identifier: train.identifier, should_fetch_weather: fetchWeather) ?? [:]
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
        let stops_updated = results["stops"] as? [[String:Any]] ?? []
        for stop in today_stops {
            /// get the stop updated whose name correspond to the today stops
            guard let stop_updated = stops_updated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }

            let newPlatform = stop_updated["platform"] as? String ?? ""
            let newWeather = stop_updated["weather"] as? String ?? ""
            let newStatus = stop_updated["status"] as? Int ?? 0
            let newCompleted = stop_updated["is_completed"] as? Bool ?? false
            let newInStation = stop_updated["is_in_station"] as? Bool ?? false
            let newDepDelay = stop_updated["dep_delay"] as? Int ?? 0
            let newArrDelay = stop_updated["arr_delay"] as? Int ?? 0
            let newDepEff = stop_updated["dep_time_eff"] as? Date ?? .distantPast
            let newArrEff = stop_updated["arr_time_eff"] as? Date ?? .distantPast

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

        stop_summary = StopSummary.calculate(in: stops)

        // update calendar event if exists
        if train.calendarEventIdentifier != nil,
           let settings = profiles.first?.calendarSettings {
            await CalendarManager.shared.syncTrainEvent(
                train: train,
                stops: today_stops,
                seats: seats,
                titleFormat: settings.titleFormat,
                calendarIdentifier: settings.calendarIdentifier,
                travelTime: settings.travelTime
            )
        }
        
        try? model_context.save()
        if fetchWeather {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Previews

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
        DetailsView(train: train, show_ticket_initially: .constant(false), ticketSeatID: .constant(nil))
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
