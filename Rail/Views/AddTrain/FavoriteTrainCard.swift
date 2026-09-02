import SwiftUI

/// One saved journey, laid out like the Choose Train solution rows.
struct FavoriteTrainCard: View {
    let favorite: Favorite
    let isLoading: Bool
    let isUnavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(favorite.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: UIFont.preferredFont(forTextStyle: .headline).lineHeight * 0.9)

                Text(favorite.number)
                    .font(.headline).fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(favorite.stop_names.first ?? "")
                    Spacer(minLength: 12)
                    if let time = favorite.stop_ref_times.first {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
                HStack {
                    Text(favorite.stop_names.last ?? "")
                    Spacer(minLength: 12)
                    if let time = favorite.stop_ref_times.last {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .fontDesign(appFontDesign)
        .padding(.vertical, 4)
        .shimmering(isLoading)
    }
}
