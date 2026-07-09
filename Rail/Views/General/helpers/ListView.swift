import SwiftUI
import SwiftData

struct ListView: View {
    // MARK: - variables
    // data variables
    let train: Train
    let stops: [Stop]
    let summary: StopSummary
    var now: Date = Date()
    
    // MARK: - main view
    var body: some View {
        if now < summary.lastNoIssues.arr_time_eff {
            VStack(spacing: 8) {
                // MARK: - logo + number
                HStack(spacing: 4) {
                    Image(train.logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                    
                    Text(train.number)
                        .font(.title3)
                        .fontDesign(app_font_design)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                .padding(.horizontal).padding(.top)
                
                // MARK: - departure and arrival stops
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.firstNoIssues.name)
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.red)
                                .monospacedDigit()
                        } else if now >= (stops.first?.dep_time_id ?? now) && summary.firstNoIssues.dep_delay != 0 {
                            Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(summary.firstNoIssues.dep_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        } else {
                            Text(summary.firstNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay == 0 ? Color.green : Color.primary)
                                .monospacedDigit()
                        }
                    }
                    
                    HStack {
                        Text(summary.lastNoIssues.name)
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.red)
                                .monospacedDigit()
                        } else if now >= stops.first?.dep_time_id ?? now && summary.lastNoIssues.arr_delay != 0 {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(summary.lastNoIssues.arr_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay == 0 {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.green)
                                .monospacedDigit()
                        } else {
                            Text(summary.lastNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.primary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal).padding(.top, 8)
                
                // MARK: - bottom bar
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
                } else if now < summary.firstNoIssues.dep_time_id {
                    HStack(spacing: 8) {
                        ZStack {
                            let dep_time = {
                                if summary.first.dep_time_eff != .distantPast && Calendar.current.isDateInToday(summary.first.dep_time_eff) {
                                    return summary.first.dep_time_eff
                                } else {
                                    return summary.first.dep_time_id
                                }
                            }()
                            
                            let time_to_departure = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: dep_time)
                            let day = time_to_departure.day ?? 0
                            let hour = time_to_departure.hour ?? 0
                            let minute = time_to_departure.minute ?? 0
                            
                            let time_string: String = {
                                if day > 0 {
                                    return "\(NSLocalizedString("Departure on", comment: "")) \(dep_time.formatted(date: .abbreviated, time: .omitted))"
                                } else if hour > 0 && minute > 0 {
                                    return "\(NSLocalizedString("Departure in", comment: "")) \(hour)h \(minute)m"
                                } else if hour > 0 && minute == 0 {
                                    return "\(NSLocalizedString("Departure in", comment: "")) \(hour)h"
                                } else if minute > 0 {
                                    return "\(NSLocalizedString("Departure in", comment: "")) \(minute)m"
                                } else {
                                    return "Partenza imminente"
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
                        .padding(.leading, 8).padding(.vertical, 8)
                        .padding(.trailing, (now > summary.first.dep_time_id || Calendar.current.isDate(summary.first.dep_time_id, inSameDayAs: now)) && summary.first.platform != "-" ? 0 : 8)
                        
                        if (now > summary.first.dep_time_id || Calendar.current.isDate(summary.first.dep_time_id, inSameDayAs: now)) && summary.first.platform != "-" {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right")
                                    .padding(.vertical, 8).padding(.leading)
                                Text(summary.first.platform)
                                    .fontDesign(app_font_design)
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
                                .fontDesign(app_font_design)
                                .foregroundStyle(train.delay > 0 ? .red : .green)
                                .padding(.vertical, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .background(train.delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .cornerRadius(16)
                        .padding(.leading, 8).padding(.vertical, 8)
                        .padding(.trailing, summary.last.platform == "-" ? 8 : 0)
                        
                        if summary.last.platform != "-" {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.right")
                                    .padding(.vertical, 8).padding(.leading)
                                Text(summary.last.platform)
                                    .fontDesign(app_font_design)
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
        } else if now >= summary.last.arr_time_eff {
            HStack{
                VStack {
                    Text("\(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.day()))")
                        .font(.title)
                        .fontDesign(app_font_design)
                        .fontWeight(.semibold)
                    Text("\(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.month()))")
                        .font(.title)
                        .fontDesign(app_font_design)
                        .fontWeight(.semibold)
                    Text("\(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.year()))")
                        .font(.title)
                        .fontDesign(app_font_design)
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
                            .fontDesign(app_font_design)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                        
                        Spacer()
                    }
                    .padding(.trailing).padding(.top)
                    
                    // departure and arrival stops with time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(summary.firstNoIssues.name)
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.red)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay != 0 {
                                Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(summary.firstNoIssues.dep_delay > 0 ? Color.red : Color.green)
                                    .monospacedDigit()
                            } else {
                                Text(summary.firstNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay == 0 ? Color.green : Color.primary)
                                    .monospacedDigit()
                            }
                        }
                        
                        HStack {
                            Text(summary.lastNoIssues.name)
                                .font(.subheadline)
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.red)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay != 0 {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(summary.lastNoIssues.arr_delay > 0 ? Color.red : Color.green)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay == 0 {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.green)
                                    .monospacedDigit()
                            } else {
                                Text(summary.lastNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.primary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.trailing).padding(.top, 8)
                    
                    // bottom bar
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
                    } else {
                    ZStack {
                        let delay_string: String = {
                            if summary.lastNoIssues.arr_delay < 0 {
                                let delay = abs(summary.lastNoIssues.arr_delay)
                                if delay >= 60 {
                                    let hours = delay / 60
                                    let minutes = delay % 60
                                    return "\(NSLocalizedString("Early of", comment: "")) \(hours)h \(minutes)m"
                                }
                                return "\(NSLocalizedString("Early of", comment: "")) \(delay)m"
                            } else if summary.lastNoIssues.arr_delay == 0 {
                                return "\(NSLocalizedString("On time", comment: "")) "
                            } else {
                                if summary.lastNoIssues.arr_delay >= 60 {
                                    let hours = summary.lastNoIssues.arr_delay / 60
                                    let minutes = summary.lastNoIssues.arr_delay % 60
                                    return "\(NSLocalizedString("Late of", comment: "")) \(hours)h \(minutes)m"
                                }
                                return "\(NSLocalizedString("Late of", comment: "")) \(summary.lastNoIssues.arr_delay)m"
                            }
                        }()

                        Text(delay_string)
                            .font(.subheadline)
                            .fontDesign(app_font_design)
                            .foregroundStyle(summary.lastNoIssues.arr_delay > 0 ? .red : .green)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(summary.lastNoIssues.arr_delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
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
