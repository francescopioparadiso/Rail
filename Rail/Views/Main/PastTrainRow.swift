import SwiftUI

struct PastTrainRow: View, Equatable {
    // MARK: - Properties

    let item: TrainRowItem
    let now: Date
    let isFirst: Bool
    let isLast: Bool

    // MARK: - Computed

    private var showsDivider: Bool { !isLast }

    /// Space either side of the rule between rows, held inside the rows it separates
    /// so each row's cell begins and ends on the rule itself.
    private static let ruleGap: CGFloat = 6

    // MARK: - Body

    @Environment(\.selectTrain) private var selectTrain

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ListView(train: item.train, stops: item.trainStops, summary: item.summary, now: now)
                    .padding(.top, isFirst ? 4 : item.topPadding + Self.ruleGap)
                    .padding(.bottom, isLast ? 4 : item.bottomPadding + Self.ruleGap)

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
}
