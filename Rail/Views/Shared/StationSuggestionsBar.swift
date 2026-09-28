import SwiftUI

/// The floating bar of station names shown while a station is being typed, in the
/// Add Train form and on the station board alike.
struct StationSuggestionsBar: View {
    // MARK: - Properties

    let suggestions: [StationSuggestion]
    /// Whether these are the stations around the user rather than matches for
    /// what was typed, each then marked with a location glyph.
    var isNearby: Bool = false
    let onSelect: (StationSuggestion) -> Void

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { station in
                    Button {
                        onSelect(station)
                    } label: {
                        HStack(spacing: 6) {
                            if isNearby {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }

                            Text(station.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .font(.subheadline).fontWeight(.medium)
                        .fontDesign(appFontDesign)
                        .frame(height: 32)
                        .padding(.vertical, 6).padding(.horizontal, 16)
                        .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        // fade the chips at the edges, masking before the glass keeps the pill solid
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .glassEffect(.regular)
    }
}
