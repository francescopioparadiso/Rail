import SwiftUI
import SwiftData

struct ListView: View {
    // MARK: - Properties

    let train: Train
    let stops: [Stop]
    let summary: StopSummary
    var now: Date = Date()

    // MARK: - Body

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
                        .fontDesign(appFontDesign)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
                
                // MARK: - departure and arrival stops
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.firstNoIssues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.red)
                                .monospacedDigit()
                        } else if now >= (stops.first?.dep_time_id ?? now) && summary.firstNoIssues.dep_delay != 0 {
                            Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(summary.firstNoIssues.dep_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        } else {
                            Text(summary.firstNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay == 0 ? Color.green : Color.primary)
                                .monospacedDigit()
                        }
                    }
                    
                    HStack {
                        Text(summary.lastNoIssues.name)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)
                        
                        Spacer()
                        
                        if train.issue == "Treno cancellato" {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.red)
                                .monospacedDigit()
                        } else if now >= stops.first?.dep_time_id ?? now && summary.lastNoIssues.arr_delay != 0 {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(summary.lastNoIssues.arr_delay > 0 ? Color.red : Color.green)
                                .monospacedDigit()
                        } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay == 0 {
                            Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.green)
                                .monospacedDigit()
                        } else {
                            Text(summary.lastNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // MARK: - bottom bar
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
                    .padding(.bottom, 8).padding(.horizontal, 12)
                } else if now < summary.firstNoIssues.dep_time_id {
                    let depTime = {
                        if summary.first.dep_time_eff != .distantPast && Calendar.current.isDateInToday(summary.first.dep_time_eff) {
                            return summary.first.dep_time_eff
                        } else {
                            return summary.first.dep_time_id
                        }
                    }()

                    let timeToDeparture = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: depTime)
                    let day = timeToDeparture.day ?? 0
                    let hour = timeToDeparture.hour ?? 0
                    let minute = timeToDeparture.minute ?? 0

                    let timeString: LocalizedStringKey = {
                        if day > 0 {
                            return "Departure on \(depTime.formatted(date: .abbreviated, time: .omitted))"
                        } else if hour > 0 && minute > 0 {
                            return "Departure in \(hour)h \(minute)m"
                        } else if hour > 0 && minute == 0 {
                            return "Departure in \(hour)h"
                        } else if minute > 0 {
                            return "Departure in \(minute)m"
                        } else {
                            return "About to depart"
                        }
                    }()

                    let showsPlatform = (now > summary.first.dep_time_id
                        || Calendar.current.isDate(summary.first.dep_time_id, inSameDayAs: now))
                        && summary.first.platform != "-"

                    statusBar(
                        text: timeString,
                        tint: Color.primary,
                        background: Color.gray.opacity(0.15),
                        platform: showsPlatform ? summary.first.platform : nil,
                        platformIcon: "arrow.up.right"
                    )
                } else {
                    let delayString: LocalizedStringKey = {
                        if train.delay < 0 {
                            let delay = abs(train.delay)
                            if delay >= 60 {
                                return "Early of \(delay / 60)h \(delay % 60)m"
                            }
                            return "Early of \(delay)m"
                        } else if train.delay == 0 {
                            return "On time"
                        } else {
                            if train.delay >= 60 {
                                return "Late of \(train.delay / 60)h \(train.delay % 60)m"
                            }
                            return "Late of \(train.delay)m"
                        }
                    }()

                    statusBar(
                        text: delayString,
                        tint: train.delay > 0 ? .red : .green,
                        background: train.delay > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15),
                        platform: summary.last.platform == "-" ? nil : summary.last.platform,
                        platformIcon: "arrow.down.right"
                    )
                }
            }
        } else if now >= summary.last.arr_time_eff {
            HStack {
                // same calendar badge as the tickets fetched from email
                DepartureCalendarBadge(date: summary.lastNoIssues.arr_time_eff, fillsHeight: true)
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
                
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
                    .padding(.leading, 4).padding(.trailing, 16).padding(.top, 8)
                    
                    // departure and arrival stops with time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(summary.firstNoIssues.name)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.red)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay != 0 {
                                Text(summary.firstNoIssues.dep_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(summary.firstNoIssues.dep_delay > 0 ? Color.red : Color.green)
                                    .monospacedDigit()
                            } else {
                                Text(summary.firstNoIssues.dep_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(now >= summary.first.dep_time_id && summary.firstNoIssues.dep_delay == 0 ? Color.green : Color.primary)
                                    .monospacedDigit()
                            }
                        }
                        
                        HStack {
                            Text(summary.lastNoIssues.name)
                                .font(.subheadline)
                                .fontDesign(appFontDesign)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.5)
                            
                            Spacer()
                            
                            if train.issue == "Treno cancellato" {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.red)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay != 0 {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(summary.lastNoIssues.arr_delay > 0 ? Color.red : Color.green)
                                    .monospacedDigit()
                            } else if now >= summary.first.dep_time_id && summary.lastNoIssues.arr_delay == 0 {
                                Text(summary.lastNoIssues.arr_time_eff.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.green)
                                    .monospacedDigit()
                            } else {
                                Text(summary.lastNoIssues.arr_time_id.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline)
                                    .fontDesign(appFontDesign)
                                    .foregroundStyle(Color.primary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.leading, 4).padding(.trailing, 16)
                    
                    // no delay chip here: the arrival time above is already tinted by the delay
                    if train.issue == "Treno cancellato" {
                        Text(train.issue)
                            .font(.subheadline)
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.red)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(16)
                            .padding(.trailing, 12)
                    }
                }
                .padding(.vertical, 4)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Subviews

    // full-width status bar, with the platform kept alongside it in its own yellow chip
    private func statusBar(
        text: LocalizedStringKey,
        tint: Color,
        background: Color,
        platform: String?,
        platformIcon: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline)
                .fontDesign(appFontDesign)
                .foregroundStyle(tint)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(background)
                .cornerRadius(16)

            if let platform {
                HStack(spacing: 4) {
                    Image(systemName: platformIcon)
                    Text(platform)
                        .fontDesign(appFontDesign)
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(Color.yellow.opacity(0.5))
                .cornerRadius(16)
            }
        }
        .padding(.bottom, 8).padding(.horizontal, 12)
    }
}
