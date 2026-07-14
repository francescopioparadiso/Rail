import SwiftUI

struct TodayTrainRow: View, Equatable {
    let item: TrainRowItem
    let now: Date
    let manualRefreshCounter: Int

    static func == (lhs: TodayTrainRow, rhs: TodayTrainRow) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.now == rhs.now
            && lhs.manualRefreshCounter == rhs.manualRefreshCounter
            && lhs.item.train.last_update_time == rhs.item.train.last_update_time
            && lhs.item.train.delay == rhs.item.train.delay
            && lhs.item.train.issue == rhs.item.train.issue
            && lhs.item.summary.firstNoIssues.dep_time_eff == rhs.item.summary.firstNoIssues.dep_time_eff
            && lhs.item.summary.lastNoIssues.arr_time_eff == rhs.item.summary.lastNoIssues.arr_time_eff
            && lhs.item.summary.first.platform == rhs.item.summary.first.platform
            && lhs.item.summary.last.platform == rhs.item.summary.last.platform
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)
                    .padding(.top, item.topPadding)
                    .padding(.bottom, item.bottomPadding)

                NavigationLink(value: item.train) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .opacity(0)
            }

            if let connection = item.connection {
                ConnectionIntervalView(
                    durationString: connection.durationString,
                    totalMinutes: connection.totalMinutes,
                    connectionStatus: connection.connectionStatus,
                    station: connection.station,
                    weather: connection.weather,
                    index: connection.index,
                    total: connection.total,
                    manualRefreshCounter: manualRefreshCounter
                )
            }
        }
    }
}

struct PastTrainRow: View, Equatable {
    let item: TrainRowItem
    let now: Date

    static func == (lhs: PastTrainRow, rhs: PastTrainRow) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.now == rhs.now
            && lhs.item.train.last_update_time == rhs.item.train.last_update_time
            && lhs.item.train.delay == rhs.item.train.delay
            && lhs.item.train.issue == rhs.item.train.issue
            && lhs.item.summary.lastNoIssues.arr_time_eff == rhs.item.summary.lastNoIssues.arr_time_eff
    }

    var body: some View {
        ZStack {
            ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)

            NavigationLink(value: item.train) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .opacity(0)
        }
    }
}
