import SwiftUI

struct PastTrainRow: View, Equatable {
    let item: TrainRowItem
    let now: Date
    let isFirst: Bool
    let isLast: Bool

    private var showsDivider: Bool { !isLast }

    static func == (lhs: PastTrainRow, rhs: PastTrainRow) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isFirst == rhs.isFirst
            && lhs.isLast == rhs.isLast
            && lhs.now == rhs.now
            && lhs.item.train.last_update_time == rhs.item.train.last_update_time
            && lhs.item.train.delay == rhs.item.train.delay
            && lhs.item.train.issue == rhs.item.train.issue
            && lhs.item.summary.lastNoIssues.arr_time_eff == rhs.item.summary.lastNoIssues.arr_time_eff
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)
                    .padding(.top, isFirst ? 4 : item.topPadding)
                    .padding(.bottom, isLast ? 4 : item.bottomPadding)

                NavigationLink(value: item.train) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .opacity(0)
            }

            if showsDivider {
                Divider()
                    .padding(.vertical, 6)
            }
        }
    }
}
