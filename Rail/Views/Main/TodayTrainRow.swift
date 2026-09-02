import SwiftUI

struct TodayTrainRow: View, Equatable {
    // MARK: - Properties

    let item: TrainRowItem
    let now: Date
    let manualRefreshCounter: Int
    let isFirst: Bool
    let isLast: Bool

    // MARK: - Computed

    /// A connected pair already reads as one block, so it gets no rule between its legs.
    private var showsDivider: Bool { !isLast && item.connection == nil }

    /// An arrived train leads with the calendar badge, inset 12pt; every other row leads
    /// with text, inset 16pt. At the top of the card the inset has to match whichever it is.
    private var firstRowTopPadding: CGFloat {
        now >= item.summary.last.arr_time_eff ? 4 : 8
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)
                    .padding(.top, isFirst ? firstRowTopPadding : item.topPadding)
                    .padding(.bottom, isLast ? 4 : item.bottomPadding)

                NavigationLink(value: item.train) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .opacity(0)
            }

            if let connection = item.connection {
                ConnectionDivider(minutes: connection.totalMinutes)
                    .padding(.horizontal, 12)
            }

            if showsDivider {
                Divider()
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Actions

    static func == (lhs: TodayTrainRow, rhs: TodayTrainRow) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isFirst == rhs.isFirst
            && lhs.isLast == rhs.isLast
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
}
