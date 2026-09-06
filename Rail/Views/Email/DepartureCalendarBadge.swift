import SwiftUI

struct DepartureCalendarBadge: View {
    // MARK: - Properties

    let date: Date
    /// Lets the badge grow to the height of its row instead of the fixed email-list size.
    var fillsHeight: Bool = false
    /// Breathing room above and below the date. Enough of it makes the badge taller
    /// than the text beside it, which then sets the height of the whole row.
    var verticalPadding: CGFloat = 0

    /// `formatted` reads the system locale on its own, so the month has to be told
    /// which language the surrounding view is being shown in.
    @Environment(\.locale) private var locale

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated).locale(locale)).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)

            Text(date.formatted(.dateTime.day().locale(locale)))
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
        .fontDesign(appFontDesign)
        .padding(.vertical, verticalPadding)
        .frame(width: 58, height: fillsHeight ? nil : 88)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}
