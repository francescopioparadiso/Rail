import SwiftUI
import SwiftData

extension Stop {
    static func placeholder() -> Stop {
        Stop(
            id: UUID(),
            name: "N/A",
            platform: "N/A",
            weather: "N/A",
            is_selected: false,
            status: 0,
            is_completed: false,
            is_in_station: false,
            dep_delay: 0,
            arr_delay: 0,
            dep_time_id: .distantPast,
            arr_time_id: .distantPast,
            dep_time_eff: .distantPast,
            arr_time_eff: .distantPast,
            ref_time: .distantPast
        )
    }
}


struct ListView: View {
    let train: Train
    let stops: [Stop]
    
    var first_stop: Stop {
        stops.first(where: { $0.is_selected }) ?? stops.first ?? Stop.placeholder()
    }
    
    var last_stop: Stop {
        stops.last(where: { $0.is_selected }) ?? Stop.placeholder()
    }
    
    var first_stop_no_issues: Stop {
        stops.first(where: { $0.status != 3 && $0.is_selected }) ?? stops.first ?? Stop.placeholder()
    }
    
    var last_stop_no_issues: Stop {
        stops.last(where: { $0.status != 3 && $0.is_selected }) ?? stops.last ?? Stop.placeholder()
    }

    var body: some View {
        if Date() < last_stop_no_issues.arr_time_eff {
            VStack(spacing: 8) {
                // logo + number
                HStack(spacing: 4) {
                    Image(train.logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                    
                    Text(train.number)
                        .font(.title3)
                        .fontDesign(appFontDesign)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                .padding(.horizontal).padding(.top)
                
                // departure and arrival stops with time
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(first_stop_no_issues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.red)
                        } else if Date() >= first_stop.dep_time_id && first_stop_no_issues.dep_delay != 0 {
                            Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(first_stop_no_issues.dep_delay > 0 ? Color.red : Color.green)
                        } else {
                            Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Date() >= first_stop.dep_time_id && first_stop_no_issues.dep_delay == 0 ? Color.green : Color.primary)
                        }
                    }
                    
                    HStack {
                        Text(last_stop_no_issues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.red)
                        } else if Date() >= first_stop.dep_time_id && last_stop_no_issues.arr_delay != 0 {
                            Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? Color.red : Color.green)
                        } else if Date() >= first_stop.dep_time_id && last_stop_no_issues.arr_delay == 0 {
                            Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
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
                
                // bottom bar
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
                } else if Date() < first_stop_no_issues.dep_time_id {
                    HStack(spacing: 8) {
                        ZStack {
                            let time_to_departure = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: first_stop.dep_time_id)
                            let day = time_to_departure.day ?? 0
                            let hour = time_to_departure.hour ?? 0
                            let minute = time_to_departure.minute ?? 0
                            
                            let time_string: String = {
                                if day > 0 {
                                    return "\(NSLocalizedString("Departure on", comment: ""))  \(first_stop.dep_time_id.formatted(date: .abbreviated, time: .omitted))"
                                } else if hour > 0 {
                                    return "\(NSLocalizedString("Departure in", comment: ""))  \(hour)h\(minute)m"
                                } else if minute > 0 {
                                    return "\(NSLocalizedString("Departure in", comment: "")) \(minute)m"
                                } else {
                                    return "\(NSLocalizedString("Departure in moments", comment: "")) "
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
                        .padding(.leading, 8).padding(.vertical, 8)
                        .padding(.trailing, (Date() > first_stop.dep_time_id || Calendar.current.isDate(first_stop.dep_time_id, inSameDayAs: Date())) && first_stop.platform != "-" ? 0 : 8)
                        
                        if (Date() > first_stop.dep_time_id || Calendar.current.isDate(first_stop.dep_time_id, inSameDayAs: Date())) && first_stop.platform != "-" {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right")
                                    .padding(.vertical, 8).padding(.leading)
                                Text(first_stop.platform)
                                    .fontDesign(appFontDesign)
                                    .padding(.vertical, 8).padding(.trailing)
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .background(Color.yellow.opacity(0.5))
                            .cornerRadius(16)
                            .padding(.trailing, 8).padding(.vertical, 8)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ZStack {
                            let delay_string: String = {
                                if train.delay < 0 {
                                    let delay = abs(train.delay)
                                    if delay >= 60 {
                                        let hours = delay / 60
                                        let minutes = delay % 60
                                        return "\(NSLocalizedString("Early of", comment: "")) \(hours)h \(minutes)m"
                                    }
                                    return "\(NSLocalizedString("Early of", comment: "")) \(delay)m"
                                } else if train.delay == 0 {
                                    return "\(NSLocalizedString("On time", comment: ""))"
                                } else {
                                    if train.delay >= 60 {
                                        let hours = train.delay / 60
                                        let minutes = train.delay % 60
                                        return "\(NSLocalizedString("Late of", comment: "")) \(hours)h \(minutes)m"
                                    }
                                    return "\(NSLocalizedString("Late of", comment: "")) \(train.delay)m"
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
                        .padding(.leading, 8).padding(.vertical, 8)
                        .padding(.trailing, last_stop.platform == "-" ? 8 : 0)
                        
                        if last_stop.platform != "-" {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.right")
                                    .padding(.vertical, 8).padding(.leading)
                                Text(last_stop.platform)
                                    .fontDesign(appFontDesign)
                                    .padding(.vertical, 8).padding(.trailing)
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .background(Color.yellow.opacity(0.5))
                            .cornerRadius(16)
                            .padding(.trailing, 8).padding(.vertical, 8)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .inset(by: 0.5)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color.primary.opacity(0.5))
            )
        } else if Date() >= last_stop.arr_time_eff {
            HStack{
                VStack {
                    Text("\(last_stop_no_issues.arr_time_eff.formatted(.dateTime.day()))")
                        .font(.title)
                        .fontDesign(appFontDesign)
                        .fontWeight(.semibold)
                    Text("\(last_stop_no_issues.arr_time_eff.formatted(.dateTime.month()))")
                        .font(.title)
                        .fontDesign(appFontDesign)
                        .fontWeight(.semibold)
                    Text("\(last_stop_no_issues.arr_time_eff.formatted(.dateTime.year()))")
                        .font(.title)
                        .fontDesign(appFontDesign)
                        .fontWeight(.semibold)
                }
                .frame(maxHeight: .infinity)
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(16)
                .padding(.leading, 8).padding(.vertical, 8)
                
                VStack(spacing: 8) {
                    // logo + number
                    HStack(spacing: 4) {
                        Image(train.logo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                        
                        Text(train.number)
                            .font(.title3)
                            .fontDesign(appFontDesign)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                        
                        Spacer()
                    }
                    .padding(.trailing).padding(.top)
                    
                    // departure and arrival stops with time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(first_stop_no_issues.name)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.red)
                            } else if Date() >= first_stop.dep_time_id && first_stop_no_issues.dep_delay != 0 {
                                Text(first_stop_no_issues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(first_stop_no_issues.dep_delay > 0 ? Color.red : Color.green)
                            } else {
                                Text(first_stop_no_issues.dep_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Date() >= first_stop.dep_time_id && first_stop_no_issues.dep_delay == 0 ? Color.green : Color.primary)
                            }
                        }
                        
                        HStack {
                            Text(last_stop_no_issues.name)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.red)
                            } else if Date() >= first_stop.dep_time_id && last_stop_no_issues.arr_delay != 0 {
                                Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? Color.red : Color.green)
                            } else if Date() >= first_stop.dep_time_id && last_stop_no_issues.arr_delay == 0 {
                                Text(last_stop_no_issues.arr_time_eff.formatted(.dateTime.hour().minute()))
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
                    .padding(.trailing).padding(.top, 8)
                    
                    // bottom bar
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
                    } else {
                        ZStack {
                            let delay_string: String = {
                                if last_stop_no_issues.arr_delay < 0 {
                                    let delay = abs(last_stop_no_issues.arr_delay)
                                    if delay >= 60 {
                                        let hours = delay / 60
                                        let minutes = delay % 60
                                        return "\(NSLocalizedString("Early of", comment: "")) \(hours)h \(minutes)m"
                                    }
                                    return "\(NSLocalizedString("Early of", comment: "")) \(delay)m"
                                } else if last_stop_no_issues.arr_delay == 0 {
                                    return "\(NSLocalizedString("On time", comment: "")) "
                                } else {
                                    if last_stop_no_issues.arr_delay >= 60 {
                                        let hours = last_stop_no_issues.arr_delay / 60
                                        let minutes = last_stop_no_issues.arr_delay % 60
                                        return "\(NSLocalizedString("Late of", comment: "")) \(hours)h \(minutes)m"
                                    }
                                    return "\(NSLocalizedString("Late of", comment: "")) \(last_stop_no_issues.arr_delay)m"
                                }
                            }()
                            
                            Text(delay_string)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(last_stop_no_issues.arr_delay > 0 ? .red : .green)
                                .padding(.vertical, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .background(last_stop_no_issues.arr_delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .cornerRadius(16)
                        .padding(.vertical, 8).padding(.trailing, 8)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .inset(by: 0.5)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color.primary.opacity(0.5))
            )
        }
    }
}

/*
#Preview {
    // MARK: - 1️⃣ Not Yet Departed Train
    let upcomingStops = [
        Stop(
            id: UUID(),
            name: "Napoli Centrale",
            platform: "5",
            status: 0,
            is_completed: false,
            is_in_station: false,
            delay: 0,
            dep_time_id: Calendar.current.date(byAdding: .minute, value: 125, to: Date())!,
            arr_time_id: .distantPast,
            dep_time_eff: Calendar.current.date(byAdding: .minute, value: 125, to: Date())!,
            arr_time_eff: .distantPast,
            ref_time: Date()
        ),
        Stop(
            id: UUID(),
            name: "Bologna Centrale",
            platform: "2",
            status: 0,
            is_completed: false,
            is_in_station: false,
            delay: 0,
            dep_time_id: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            arr_time_id: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            dep_time_eff: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            arr_time_eff: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            ref_time: Date()
        )
    ]

    let upcomingTrain = Train(
        id: UUID(),
        logo: "FR",
        number: "9513",
        identifier: "9513_MI-FI",
        provider: "Trenitalia",
        last_upadate_time: Date(),
        delay: 0,
        direction: "Firenze S.M.N.",
        seats: [],
        issue: ""
    )

    // MARK: - 2️⃣ Running Train
    let runningStops = [
        Stop(
            id: UUID(),
            name: "Roma Termini",
            platform: "3",
            status: 0,
            is_completed: true,
            is_in_station: false,
            delay: 3,
            dep_time_id: Calendar.current.date(byAdding: .minute, value: -30, to: Date())!,
            arr_time_id: .distantPast,
            dep_time_eff: Calendar.current.date(byAdding: .minute, value: -27, to: Date())!,
            arr_time_eff: .distantPast,
            ref_time: Date()
        ),
        Stop(
            id: UUID(),
            name: "Napoli Centrale",
            platform: "4",
            status: 0,
            is_completed: false,
            is_in_station: false,
            delay: 3,
            dep_time_id: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            arr_time_id: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
            dep_time_eff: Calendar.current.date(byAdding: .minute, value: 63, to: Date())!,
            arr_time_eff: Calendar.current.date(byAdding: .minute, value: 63, to: Date())!,
            ref_time: Date()
        )
    ]

    let runningTrain = Train(
        id: UUID(),
        logo: "FR",
        number: "9520",
        identifier: "9520_RM-NA",
        provider: "Trenitalia",
        last_upadate_time: Date(),
        delay: 3,
        direction: "Napoli Centrale",
        seats: ["Carriage 7 - Seat 32A"],
        issue: ""
    )

    // MARK: - 3️⃣ Arrived Train
    let arrivedStops = [
        Stop(
            id: UUID(),
            name: "Torino Porta Nuova",
            platform: "8",
            status: 0,
            is_completed: true,
            is_in_station: false,
            delay: 0,
            dep_time_id: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!,
            arr_time_id: .distantPast,
            dep_time_eff: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!,
            arr_time_eff: .distantPast,
            ref_time: Date()
        ),
        Stop(
            id: UUID(),
            name: "Milano Centrale",
            platform: "6",
            status: 0,
            is_completed: true,
            is_in_station: true,
            delay: 2,
            dep_time_id: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!,
            arr_time_id: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!,
            dep_time_eff: Calendar.current.date(byAdding: .minute, value: -58, to: Date())!,
            arr_time_eff: Calendar.current.date(byAdding: .minute, value: -58, to: Date())!,
            ref_time: Date()
        )
    ]

    let arrivedTrain = Train(
        id: UUID(),
        logo: "FR",
        number: "9501",
        identifier: "9501_TO-MI",
        provider: "trenitalia",
        last_upadate_time: Date(),
        delay: 2,
        direction: "Milano Centrale",
        seats: [],
        issue: ""
    )

    // MARK: - Combine All Three
    ScrollView {
        VStack(spacing: 24) {
            ListView(train: runningTrain, stops: runningStops)
            ListView(train: upcomingTrain, stops: upcomingStops)
            ListView(train: arrivedTrain, stops: arrivedStops)
        }
        .padding()
    }
}
*/
