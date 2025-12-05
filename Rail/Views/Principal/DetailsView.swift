import SwiftUI
import SwiftData

enum seats_input_type {
    case carriage
    case seat
    case name
}

struct DetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    let train: Train
    let stops: [Stop]
    
    @State private var seats_sheet: Bool = false
    @State private var showAllStops: Bool = false
    
    @State private var newCarriage: String = ""
    @State private var newSeat: String = ""
    @State private var newName: String = ""
    
    @FocusState private var seats_focus: seats_input_type?
    
    var first_stop: Stop {
        showAllStops ?
        stops.first ?? Stop.placeholder() :
        stops.first(where: { $0.is_selected }) ?? stops.first ?? Stop.placeholder()
    }
    var last_stop: Stop {
        showAllStops ?
        stops.last ?? Stop.placeholder() :
        stops.last(where: { $0.is_selected }) ?? stops.last ?? Stop.placeholder()
    }
    var first_stop_no_issues: Stop {
        showAllStops ?
        stops.first(where: { $0.status != 3 }) ?? stops.first ?? Stop.placeholder() :
        stops.first(where: { $0.status != 3 && $0.is_selected }) ?? Stop.placeholder()
    }
    var last_stop_no_issues: Stop {
        showAllStops ?
        stops.last(where: { $0.status != 3 }) ?? stops.last ?? Stop.placeholder() :
        stops.last(where: { $0.status != 3 && $0.is_selected}) ?? stops.last ?? Stop.placeholder()
    }
    
    var first_index: Int {
        stops.startIndex
    }
    var last_index: Int {
        stops.endIndex
    }
    var first_index_no_issues: Int {
        stops.firstIndex(where: { $0.status != 3 }) ?? (stops.indices.first ?? 0)
    }
    var last_index_no_issues: Int {
        stops.lastIndex(where: { $0.status != 3 }) ?? (stops.indices.last ?? 0)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - main content
            ScrollView(.vertical, showsIndicators: false) {
                // MARK: - train logo and number
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
                
                // MARK: - departure and arrival
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(first_stop_no_issues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                            .strikethrough(train.issue == "Treno cancellato")
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .strikethrough()
                                .foregroundStyle(Color.red)
                        } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                            HStack {
                                if first_stop_no_issues.dep_delay != 0 {
                                    Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .strikethrough()
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(first_stop_no_issues.dep_delay > 0 ? Color.red : Color.green)
                            }
                        } else {
                            Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Date() >= first_stop_no_issues.dep_time_id && first_stop_no_issues.dep_delay == 0 ? Color.green : Color.primary)
                        }
                    }
                    
                    HStack {
                        Text(last_stop_no_issues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(train.issue == "Treno cancellato" ? Color.red : Color.primary)
                            .strikethrough(train.issue == "Treno cancellato")
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .strikethrough()
                                .foregroundStyle(Color.red)
                        } else if Date() >= first_stop.dep_time_id || Calendar.current.isDateInToday(first_stop.dep_time_id) {
                            HStack {
                                if last_stop_no_issues.arr_delay != 0 {
                                    Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .strikethrough()
                                        .foregroundStyle(Color.secondary)
                                }
                                
                                Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? Color.red : Color.green)
                            }
                        } else if Date() >= first_stop.dep_time_id && last_stop.arr_delay == 0 {
                            Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.green)
                        } else {
                            Text(last_stop_no_issues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
                .padding(.horizontal).padding(.top, 8)
                
                // MARK: - delay bar
                if Date() < first_stop.dep_time_id {
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
                                return "Partenza il \(dep_time.formatted(date: .abbreviated, time: .omitted))"
                            } else if hour > 0 && minute > 0 {
                                return "Partenza in \(hour)h\(minute)m"
                            } else if hour > 0 && minute == 0 {
                                return "Partenza in \(hour)h"
                            } else if minute > 0 {
                                return "Partenza in \(minute)m"
                            } else {
                                return "Partenza imminente"
                            }
                        }()
                        
                        Text(time_string)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .padding(.vertical, 8).padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                } else if Date() > last_stop.arr_time_eff {
                    HStack (spacing: 8) {
                        ZStack {
                            Text("Arrivato il \(last_stop_no_issues.arr_time_eff.formatted(date: .abbreviated, time: .omitted))")
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
                                        return "In orario"
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
                                    .fontDesign(appFontDesign)
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
                                    return "In anticipo di \(hours)h \(minutes)m"
                                }
                                return "In anticipo di \(delay)m"
                            } else if train.delay == 0 {
                                return "In orario"
                            } else {
                                if train.delay >= 60 {
                                    let hours = train.delay / 60
                                    let minutes = train.delay % 60
                                    return "In ritardo di \(hours)h \(minutes)m"
                                }
                                return "In ritardo di \(train.delay)m"
                            }
                        }()
                        
                        Text(delay_string)
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
                
                // MARK: - other info
                HStack(spacing: 16) {
                    if !train.direction.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "train.side.front.car")
                            Text(train.direction)
                        }
                        .font(.caption)
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.secondary)
                    }
                    
                    if distance_between_stations(from: first_stop.name, to: last_stop.name) ?? 0 != 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                            Text("\(distance_between_stations(from: first_stop.name, to: last_stop.name) ?? 0) km")
                        }
                        .font(.caption)
                        .fontDesign(appFontDesign)
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
                            .fontDesign(appFontDesign)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }
                
                // MARK: - stops list
                let stops_to_show = showAllStops ? stops : stops.filter { $0.is_selected }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(stops_to_show.count) fermate")
                            .font(.footnote)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if (stops.filter{ $0.is_selected }).count != stops.count {
                            Button {
                                showAllStops.toggle()
                            } label: {
                                HStack {
                                    Image(systemName: showAllStops ? "eye.slash" : "eye" )
                                        .fontWeight(.semibold)
                                    
                                    Text(showAllStops ? "Mostra meno" : "Mostra tutte")
                                }
                                .font(.footnote)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Color.gray.opacity(0.15))
                        }
                    }
                    
                    Divider()
                    
                    LazyVStack {
                        ForEach(stops_to_show.indices, id: \.self) { index in
                            let stop = stops_to_show[index]
                            
                            HStack(spacing: 8) {
                                // MARK: - Stop status
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
                                
                                // MARK: - Stop info
                                HStack {
                                    // MARK: - Time
                                    VStack(alignment: .leading, spacing: 4) {
                                        if Date() >= first_stop_no_issues.dep_time_id || Calendar.current.isDateInToday(first_stop_no_issues.dep_time_id) {
                                            Text(stop.weather)
                                                .font(.caption)
                                                .fontDesign(appFontDesign)
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
                                            .fontDesign(appFontDesign)
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
                                            .fontDesign(appFontDesign)
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
                                            .fontDesign(appFontDesign)
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
                                                        .fontDesign(appFontDesign)
                                                        .foregroundStyle(delay_type > 0 ? Color.red : Color.green)
                                                        .padding(.vertical, 8).padding(.horizontal)
                                                }
                                                .background(delay_type > 0 ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                                .cornerRadius(16)
                                            } else if stop.is_completed {
                                                ZStack {
                                                    Text("In stazione")
                                                        .font(.footnote)
                                                        .fontDesign(appFontDesign)
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
                                                        return "In stazione"
                                                    } else if hours > 0 {
                                                        return "\(hours)h\(minutes % 60)m"
                                                    } else {
                                                        return "\(minutes)m"
                                                    }
                                                }()
                                                
                                                ZStack {
                                                    Text(time_string)
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
                                        if Date() > first_stop.dep_time_id || Calendar.current.isDate(first_stop.dep_time_id, inSameDayAs: Date()) {
                                            HStack(spacing: 4) {
                                                Image(systemName: index == 0 ? "arrow.up.right" : "arrow.down.right")
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
                    
                    // status legend
                    HStack (spacing: 8) {
                        HStack (spacing: 2) {
                            Image(systemName: "circle.fill")
                            Text("Regolare")
                        }
                        .foregroundStyle(Color.blue)
                        
                        HStack (spacing: 2) {
                            Image(systemName: "circle.fill")
                            Text("Non programmato")
                        }
                        .foregroundStyle(Color.orange)
                        
                        HStack (spacing: 2) {
                            Image(systemName: "circle.fill")
                            Text("Cancellato")
                        }
                        .foregroundStyle(Color.red)
                    }
                    .font(.system(size: 10))
                    .fontDesign(appFontDesign)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                    
                    // last updated time
                    Text("Ultimo aggiornamento: \(train.last_upadate_time.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8).padding(.bottom, !train.issue.isEmpty ? 120 : 8)
                }
                .padding()
            }
            .refreshable {
                await update_train_details()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        seats_sheet = true
                    } label: {
                        HStack {
                            Image(systemName: "figure.seated.seatbelt")
                                .fontWeight(.semibold)
                            
                            Text(train.seats.isEmpty ? "Aggiungi" : train.seats.first!.split(separator: "-").prefix(2).joined(separator: "-"))
                        }
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.gray.opacity(0.15))
                }
            }
            .sheet(isPresented: $seats_sheet) {
                seatsView(seatsFocus: $seats_focus)
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
                    .fontDesign(appFontDesign)
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
            Task { await update_train_details() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                print("📱 App returned to foreground, updating train details...")
                Task { await update_train_details() }
            }
        }
    }
    
    
    // MARK: - seat view and functions
    @ViewBuilder
    func seatsView(seatsFocus: FocusState<seats_input_type?>.Binding) -> some View {
         NavigationStack {
            List {
                let sortedSeats = train.seats.sorted { seat1, seat2 in
                    let parts1 = seat1.split(separator: "-")
                    let parts2 = seat2.split(separator: "-")
                    
                    guard parts1.count == 3 && parts2.count == 3 else {
                        return seat1 < seat2
                    }
                    
                    let carriage1 = Int(parts1[0]) ?? 0
                    let carriage2 = Int(parts2[0]) ?? 0
                    
                    if carriage1 != carriage2 {
                        return carriage1 < carriage2
                    }
                    
                    let seatNum1 = Int(parts1[1].filter { $0.isNumber }) ?? 0
                    let seatNum2 = Int(parts2[1].filter { $0.isNumber }) ?? 0
                    
                    if seatNum1 != seatNum2 {
                        return seatNum1 < seatNum2
                    }
                    
                    let seatLetter1 = parts1[1].filter { $0.isLetter }
                    let seatLetter2 = parts2[1].filter { $0.isLetter }
                    
                    if seatLetter1 != seatLetter2 {
                        return seatLetter1 < seatLetter2
                    }
                    
                    let name1 = parts1[2]
                    let name2 = parts2[2]
                    
                    return name1 < name2
                }
                
                ForEach(sortedSeats, id: \.self) { seat in
                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "train.side.rear.car")
                            Text(seat.split(separator: "-").first ?? "")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 72)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "carseat.left.fill")
                            Text(seat.split(separator: "-").dropFirst().first ?? "")
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 72)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                            Text(seat.split(separator: "-").last ?? "")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .fontDesign(appFontDesign)
                }
                .onDelete(perform: deleteSeat)
                
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "train.side.rear.car")
                        TextField("10", text: $newCarriage)
                            .keyboardType(.numbersAndPunctuation)
                            .focused(seatsFocus, equals: .carriage)
                            .onSubmit {
                                seatsFocus.wrappedValue = .seat
                            }
                            .onChange(of: newCarriage) { _, newValue in
                                if newValue.count > 2 {
                                    newCarriage = String(newValue.prefix(2))
                                } else if newValue.count == 2 {
                                    seatsFocus.wrappedValue = .seat
                                }
                            }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 72)

                    HStack(spacing: 8) {
                        Image(systemName: "carseat.left.fill")
                        TextField("15A", text: $newSeat)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($seats_focus, equals: .seat)
                            .onSubmit {
                                seatsFocus.wrappedValue = .name
                            }
                            .onChange(of: newSeat) { _, newValue in
                                if newValue.count > 3 {
                                    newSeat = String(newValue.prefix(3))
                                } else if newValue.count == 3 {
                                    seatsFocus.wrappedValue = .name
                                }
                            }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 72)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                        TextField("Francesco", text: $newName)
                            .keyboardType(.default)
                            .focused($seats_focus, equals: .name)
                            .onSubmit {
                                addNewSeat()
                            }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Spacer()
                }
                .fontDesign(appFontDesign)
            }
            .navigationTitle("I tuoi Posti")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        seats_sheet = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        addNewSeat()
                    }
                    .disabled(newCarriage.isEmpty || newSeat.isEmpty || newName.isEmpty)
                }
            }
        }
    }
    
    func deleteSeat(offsets: IndexSet) {
        let sortedSeats = train.seats.sorted { seat1, seat2 in
            let parts1 = seat1.split(separator: "-")
            let parts2 = seat2.split(separator: "-")
            
            guard parts1.count == 3 && parts2.count == 3 else {
                return seat1 < seat2
            }
            
            let carriage1 = Int(parts1[0]) ?? 0
            let carriage2 = Int(parts2[0]) ?? 0
            
            if carriage1 != carriage2 {
                return carriage1 < carriage2
            }
            
            let seatNum1 = Int(parts1[1].filter { $0.isNumber }) ?? 0
            let seatNum2 = Int(parts2[1].filter { $0.isNumber }) ?? 0
            
            if seatNum1 != seatNum2 {
                return seatNum1 < seatNum2
            }
            
            let seatLetter1 = parts1[1].filter { $0.isLetter }
            let seatLetter2 = parts2[1].filter { $0.isLetter }
            
            if seatLetter1 != seatLetter2 {
                return seatLetter1 < seatLetter2
            }
            
            let name1 = parts1[2]
            let name2 = parts2[2]
            
            return name1 < name2
        }
        
        let seatsToDelete = offsets.map { sortedSeats[$0] }
        
        for seat in seatsToDelete {
            if let index = train.seats.firstIndex(of: seat) {
                train.seats.remove(at: index)
            }
        }
    }
    
    func addNewSeat() {
        guard !newCarriage.isEmpty && !newSeat.isEmpty && !newName.isEmpty else { return }
        
        let formattedName = newName.prefix(1).uppercased() + newName.dropFirst().lowercased()
        
        let newSeatString = "\(newCarriage)-\(newSeat.uppercased())-\(formattedName)"
        train.seats.append(newSeatString)
        
        newCarriage = ""
        newSeat = ""
        newName = ""
    }
    
    // MARK: - update function
    func update_train_details() async {
        let result: [String: Any]
        
        if train.provider == "trenitalia" {
            result = await fetch_trenitalia_train_info_async(identifier: train.identifier)
        } else {
            result = await fetch_italo_train_info_async(identifier: train.identifier)
        }
        
        await MainActor.run {
            apply_result(result, to: train)
        }
    }
    
    func fetch_trenitalia_train_info_async(identifier: String) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            fetch_trenitalia_train_info(identifier: identifier) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    func fetch_italo_train_info_async(identifier: String) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            fetch_italo_train_info(identifier: identifier) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    @MainActor
    private func apply_result(_ result: [String: Any], to train: Train) {
        train.last_upadate_time = result["last_update_time"] as? Date ?? .distantPast
        train.delay = result["delay"] as? Int ?? 0
        train.direction = result["direction"] as? String ?? ""
        train.issue = result["issue"] as? String ?? ""

        if let fetchedStops = result["stops"] as? [[String: Any]] {
            for stop in stops {
                guard let fetched = fetchedStops.first(where: { ($0["name"] as? String) == stop.name }) else { continue }
                
                stop.platform = fetched["platform"] as? String ?? ""
                stop.weather = fetched["weather"] as? String ?? ""
                stop.status = fetched["status"] as? Int ?? 0
                stop.is_completed = fetched["is_completed"] as? Bool ?? false
                stop.is_in_station = fetched["is_in_station"] as? Bool ?? false
                stop.dep_delay = fetched["dep_delay"] as? Int ?? 0
                stop.arr_delay = fetched["arr_delay"] as? Int ?? 0
                stop.dep_time_eff = fetched["dep_time_eff"] as? Date ?? .distantPast
                stop.arr_time_eff = fetched["arr_time_eff"] as? Date ?? .distantPast
            }
        }

        do {
            try modelContext.save()
            print("✅ Train details updated successfully at \(Date().formatted(date: .abbreviated, time: .standard))")
        } catch {
            print("⚠️ Failed to save modelContext in DetailsView:", error)
        }
    }
}
