import SwiftUI

struct DepartureCalendarBadge: View {
    // MARK: - Properties

    let date: Date
    /// Lets the badge grow to the height of its row instead of the fixed email-list size.
    var fillsHeight: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.footnote.weight(.bold))
                .foregroundStyle(.red)

            Text(date.formatted(.dateTime.day()))
                .font(.title2.weight(.heavy))
                .foregroundStyle(.primary)
        }
        .fontDesign(appFontDesign)
        .frame(width: 58, height: fillsHeight ? nil : 88)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}
