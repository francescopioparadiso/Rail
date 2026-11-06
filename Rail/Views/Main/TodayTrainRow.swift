import SwiftUI

struct TodayTrainRow: View, Equatable {
    // MARK: - Properties

    let item: TrainRowItem
    let now: Date
    let manualRefreshCounter: Int
    let isFirst: Bool
    let isLast: Bool

    /// Set on a journey's lead row, folded or not; see `ListView`.
    var headerTrain: Train? = nil
    var extraCount: Int = 0
    var isExpanded: Bool = false
    var onToggleExpanded: (() -> Void)? = nil

    // MARK: - Computed

    /// A connected pair already reads as one block, so it gets no rule between its legs.
    private var showsDivider: Bool { !isLast && item.connection == nil }

    /// An arrived train leads with the calendar badge, inset 12pt; every other row leads
    /// with text, inset 16pt. At the top of the card the inset has to match whichever it is.
    private var firstRowTopPadding: CGFloat {
        now >= item.summary.last.arr_time_eff ? 4 : 8
    }

    /// Space either side of the rule between rows, held inside the rows it separates
    /// so each row's cell begins and ends on the rule itself. A connected pair (2pt
    /// paddings) has no rule and keeps its own spacing.
    private static let ruleGap: CGFloat = 6

    // MARK: - Body

    @Environment(\.selectTrain) private var selectTrain

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(
                    train: item.train,
                    stops: item.trainStops,
                    summary: item.summary,
                    now: now,
                    headerTrain: headerTrain,
                    extraCount: extraCount,
                    isExpanded: isExpanded,
                    onToggleExpanded: onToggleExpanded
                )
                    .padding(.top, isFirst ? firstRowTopPadding : item.topPadding + (item.topPadding > 2 ? Self.ruleGap : 0))
                    .padding(.bottom, isLast ? 4 : item.bottomPadding + (showsDivider ? Self.ruleGap : 0))

                if selectTrain == nil {
                    NavigationLink(value: item.train) {
                        EmptyView()
                    }
                    .buttonStyle(.plain)
                    .opacity(0)
                }
            }
            .applyingIf(selectTrain != nil) { row in
                row.contentShape(Rectangle())
                    .onTapGesture { selectTrain?(item.train) }
            }

            if showsDivider {
                // last line of the row, so a row's background ends exactly on it
                Divider()
            }
        }
    }

    // MARK: - Actions

    static func == (lhs: TodayTrainRow, rhs: TodayTrainRow) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.train.id == rhs.item.train.id
            && lhs.headerTrain?.id == rhs.headerTrain?.id
            && lhs.extraCount == rhs.extraCount
            && lhs.isExpanded == rhs.isExpanded
            && (lhs.onToggleExpanded == nil) == (rhs.onToggleExpanded == nil)
            && lhs.item.connection?.totalMinutes == rhs.item.connection?.totalMinutes
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
