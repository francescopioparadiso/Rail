import SwiftUI
import SwiftData
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct DetailsView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.colorScheme) var color_scheme
    @Environment(\.requestReview) var request_review
    @Environment(\.modelContext) private var model_context
    @Environment(\.scenePhase) private var scene_phase
    
    // data variables
    let train: Train
    let stops: [Stop]
    let seats: [Seat]
    @Query private var favorites: [Favorite]
    
    // state variables
    @State private var seats_sheet: Bool = false
    @State private var show_all_stops: Bool = false
    
    // computed variables
    private var is_favorite: Bool {
        let stop_names = stops.filter { $0.is_selected }.map { $0.name }
        
        let stop_ref_times = stops.filter { $0.is_selected }
            .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }
        
        let identifier = train.identifier.contains("/") ?
            String(train.identifier.split(separator: "/").dropLast().joined(separator: "/")) :
            train.identifier
        
        return favorites.contains { fav in
            guard fav.identifier == identifier else { return false }
            
            guard fav.stop_names == stop_names else { return false }
            
            let fav_ref_times = fav.stop_ref_times.map {
                $0.formatted(date: .omitted, time: .shortened)
            }
            
            return fav_ref_times == stop_ref_times
        }
    }
    
    private var first_stop: Stop {
        show_all_stops ?
        stops.first ?? Stop.placeholder() :
        stops.first(where: { $0.is_selected }) ?? stops.first ?? Stop.placeholder()
    }
    private var last_stop: Stop {
        show_all_stops ?
        stops.last ?? Stop.placeholder() :
        stops.last(where: { $0.is_selected }) ?? stops.last ?? Stop.placeholder()
    }
    private var first_stop_no_issues: Stop {
        show_all_stops ?
        stops.first(where: { $0.status != 3 }) ?? stops.first ?? Stop.placeholder() :
        stops.first(where: { $0.status != 3 && $0.is_selected }) ?? Stop.placeholder()
    }
    private var last_stop_no_issues: Stop {
        show_all_stops ?
        stops.last(where: { $0.status != 3 }) ?? stops.last ?? Stop.placeholder() :
        stops.last(where: { $0.status != 3 && $0.is_selected}) ?? stops.last ?? Stop.placeholder()
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
    
    // MARK: - main view
    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - main content
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
                        } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                            HStack {
                                if first_stop_no_issues.dep_delay != 0 {
                                    Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(app_font_design)
                                        .strikethrough()
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(first_stop_no_issues.dep_delay > 0 ? Color.red : Color.green)
                            }
                        } else {
                            Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Date() >= first_stop_no_issues.dep_time_id && first_stop_no_issues.dep_delay == 0 ? Color.green : Color.primary)
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
                        } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                            HStack {
                                if last_stop_no_issues.arr_delay != 0 {
                                    Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(app_font_design)
                                        .strikethrough()
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? Color.red : Color.green)
                            }
                        } else if Date() >= first_stop.dep_time_id && last_stop.arr_delay == 0 {
                            Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.green)
                        } else {
                            Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.primary)
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
                                return String(localized: "Departure in \(hour)h\(minute)m")
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
                                            return "\(hours)h\(minutes)m"
                                        }
                                        return "\(delay)m"
                                    } else if last_stop_no_issues.arr_delay == 0 {
                                        return String(localized: "On time")
                                    } else {
                                        if last_stop_no_issues.arr_delay >= 60 {
                                            let hours = last_stop_no_issues.arr_delay / 60
                                            let minutes = last_stop_no_issues.arr_delay % 60
                                            return "\(hours)h\(minutes)m"
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
                    
                    if distance_between_stations(from: first_stop.name, to: last_stop.name) ?? 0 != 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                            Text("\(distance_between_stations(from: first_stop.name, to: last_stop.name) ?? 0) km")
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
                                return "\(hours)h\(minutes % 60)m"
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
                
                // stops list
                let stops_to_show = show_all_stops ? stops : stops.filter { $0.is_selected }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(stops_to_show.count) stops")
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
                    
                    LazyVStack {
                        ForEach(stops_to_show.indices, id: \.self) { index in
                            let stop = stops_to_show[index]
                            
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
                                        if Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) {
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
                                                    }
                                                }
                                                
                                                if index != last_index && index != last_index_no_issues && index != stops_to_show.filter({ $0.status != 3 }).count - 1 {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "arrow.up.right.circle.fill")
                                                        Text(Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) ? stop.dep_time_eff.formatted(.dateTime.hour().minute()) : stop.dep_time_id.formatted(.dateTime.hour().minute()))
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
                                                            return "\(delay_type / 60)h\(delay_type % 60)m"
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
                                                        return "\(hours)h\(minutes % 60)m"
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
                        .padding(8).padding(.bottom, !train.issue.isEmpty ? 120 : 8)
                }
                .padding()
                .padding(.top, 24)
            }
            .refreshable {
                await update_train_details()
            }
            .toolbar {
                /// favorite button
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        
                        let stop_names = stops.filter { $0.is_selected }.map { $0.name }
                        
                        let stop_ref_times_strings = stops.filter { $0.is_selected }
                            .map { $0.ref_time.formatted(date: .omitted, time: .shortened) }
                        
                        let identifier = {
                            if train.identifier.contains("/") {
                                return train.identifier.split(separator: "/").dropLast().joined(separator: "/")
                            } else {
                                return train.identifier
                            }
                        }()
                        
                        if is_favorite {
                            // remove favorite
                            let favorite_to_remove = favorites.filter { fav in
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
                        }
                    } label: {
                        Image(systemName: is_favorite ? "heart.fill" : "heart")
                    }
                    .tint(is_favorite ? Color.red : Color.primary)
                }
                
                /// seats button
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                    .buttonStyle(.glassProminent)
                    .tint(color_scheme == .dark ? Color.black.opacity(0.1) : Color.white)
                }
            }
            .sheet(isPresented: $seats_sheet) {
                SeatsView(train: train, seats: seats)
                    .presentationDetents([.large])
            }
            
            // MARK: - issue
            if !train.issue.isEmpty {
                Button {} label: {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.largeTitle)
                            .padding(.vertical).padding(.leading)
                        
                        Text(train.issue)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical).padding(.trailing)
                        
                        Spacer(minLength: 0)
                    }
                    .fontDesign(app_font_design)
                    .foregroundStyle(Color.red)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.glassProminent)
                .tint(Color.red.opacity(0.15))
                .padding(.bottom, 16).padding(.horizontal, 16)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: request_review)
            Task { await update_train_details() }
        }
        .onChange(of: scene_phase) { _, newPhase in
            if newPhase == .active {
                Task { await update_train_details() }
            }
        }
    }
    
    // MARK: - functions
    private func update_train_details() async {
        /// condition to update
        let firstStop_refTime = stops
            .filter({ $0.id == train.id })
            .sorted(by: { $0.ref_time < $1.ref_time })
            .first?.ref_time ?? .distantPast
        
        guard Calendar.current.isDateInToday(firstStop_refTime) else { return }
        
        /// fetch new data
        let results: [String:Any] = await {
            switch train.provider {
                case "trenitalia":
                    return await TrenitaliaAPI().info(identifier: train.identifier, should_fetch_weather: true) ?? [:]
                case "italo":
                    return await ItaloAPI().info(identifier: train.identifier) ?? [:]
                default:
                    return [:]
            }
        }()
        
        /// update train data
        train.last_update_time = results["last_update_time"] as? Date ?? .distantPast
        train.delay = results["delay"] as? Int ?? 0
        train.direction = results["direction"] as? String ?? ""
        train.issue = results["issue"] as? String ?? ""
        
        /// update stops data
        let today_stops = stops.filter { $0.id == train.id }
        for stop in today_stops {
            /// get all the stops updated
            let stops_updated = results["stops"] as? [[String:Any]] ?? []
            
            /// get the stop updated whose name correspond to the today stops
            guard let stop_updated = stops_updated.first(where: { ($0["name"] as? String) == stop.name }) else { continue }
            
            /// update only the necessary fields
            stop.platform = stop_updated["platform"] as? String ?? ""
            stop.weather = stop_updated["weather"] as? String ?? ""
            stop.status = stop_updated["status"] as? Int ?? 0
            stop.is_completed = stop_updated["is_completed"] as? Bool ?? false
            stop.is_in_station = stop_updated["is_in_station"] as? Bool ?? false
            stop.dep_delay = stop_updated["dep_delay"] as? Int ?? 0
            stop.arr_delay = stop_updated["arr_delay"] as? Int ?? 0
            stop.dep_time_eff = stop_updated["dep_time_eff"] as? Date ?? .distantPast
            stop.arr_time_eff = stop_updated["arr_time_eff"] as? Date ?? .distantPast
        }
    }
}

// MARK: - previews
#Preview {
    let container: ModelContainer = {
        let schema = Schema([Train.self, Stop.self, Seat.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }()
    
    let trainId = UUID()
    let now = Date()
    
    let mockTrain = Train(
        id: trainId,
        logo: "FR",
        number: "9612",
        identifier: "TS/9612/123456",
        provider: "trenitalia",
        last_update_time: now,
        delay: 5,
        direction: "Salerno",
        seats: [],
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
        // Added the missing 'id' parameter here
        Seat(id: UUID(), trainID: trainId, name: "Marco", carriage: "5", number: "12A")
    ]

    NavigationStack {
        DetailsView(train: mockTrain, stops: mockStops, seats: mockSeats)
            .modelContainer(container)
    }
}
