import SwiftUI

/// Where a fare sits between the cheapest and dearest currently on screen.
///
/// A three-way green/amber/red split left almost everything amber once the list
/// grew, so this is a continuous ramp quantised to 11 steps: step 0 is full
/// green, step 10 full red, with 9 shades between. Interpolating through hue
/// rather than RGB keeps the midpoints yellow and orange instead of muddy brown.
struct SolutionPriceRank {
    /// 0 for the cheapest fare on screen, 1 for the dearest.
    let position: Double

    private static let steps = 10.0

    var color: Color {
        let clamped = min(max(position, 0), 1)
        let quantised = (clamped * Self.steps).rounded() / Self.steps
        // 0.33 is green, 0.16 yellow, 0.08 orange, 0 red
        return Color(hue: 0.33 * (1 - quantised), saturation: 0.9, brightness: 0.78)
    }
}

/// One journey in the Choose Train list: collapsed it shows the whole trip,
/// expanded it breaks out every leg with the connection time between them.
struct SolutionRow: View {
    // MARK: - Properties

    let solution: Solution
    let isExpanded: Bool
    let priceRank: SolutionPriceRank?
    let onToggleExpanded: () -> Void

    private static let chipHeight: CGFloat = 30

    // MARK: - Computed

    private var canExpand: Bool { solution.segments.count > 1 }

    /// Destination shown on the first block: the whole trip when collapsed,
    /// just the first leg once the legs are broken out.
    private var leadDestination: SolutionSegment? {
        isExpanded ? solution.segments.first : solution.segments.last
    }

    private var changesText: String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld changes", comment: "Number of changes on a journey"),
            solution.changeCount
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The first leg's header and route stay put across expansion — only
            // their values change — so nothing above the fold shifts or refades.
            if let first = solution.segments.first {
                VStack(alignment: .leading, spacing: 8) {
                    segmentHeader(first, extraCount: solution.segments.count - 1, showsChevron: canExpand, isLead: true)
                    route(
                        origin: first.origin,
                        destination: leadDestination?.destination ?? first.destination,
                        departure: first.departureTime,
                        arrival: isExpanded ? first.arrivalTime : solution.arrivalTime,
                        isLead: true
                    )
                }
            }

            // Remaining legs unfold underneath, pushing the chips and the rows below down.
            if isExpanded {
                ForEach(Array(solution.segments.enumerated()).dropFirst(), id: \.offset) { index, segment in
                    VStack(alignment: .leading, spacing: 12) {
                        ConnectionDivider(minutes: minutesBetween(
                            solution.segments[index - 1].arrivalTime,
                            segment.departureTime
                        ))
                        VStack(alignment: .leading, spacing: 8) {
                            segmentHeader(segment, extraCount: 0, showsChevron: false, isLead: false)
                            route(
                                origin: segment.origin,
                                destination: segment.destination,
                                departure: segment.departureTime,
                                arrival: segment.arrivalTime,
                                isLead: false
                            )
                        }
                    }
                    .transition(.opacity)
                }
            }

            chips
        }
        .fontDesign(appFontDesign)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private func segmentHeader(_ segment: SolutionSegment, extraCount: Int, showsChevron: Bool, isLead: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if segment.isUntracked {
                    Image(systemName: "tram.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if segment.isBus {
                    Image(systemName: "bus.fill")
                        .font(.title3)
                        .foregroundStyle(Color.blue)
                } else {
                    Image(segment.logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                }
            }
            .animation(isLead ? nil : .snappy, value: isExpanded)

            Text(segmentLabel(segment))
                .font(.headline).fontWeight(.semibold)
                .foregroundStyle(segmentTint(segment))
                .lineLimit(1)
                .animation(isLead ? nil : .snappy, value: isExpanded)

            if extraCount > 0 && !isExpanded {
                Text("+\(extraCount)")
                    .font(.body).fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }

            Spacer(minLength: 0)

            if showsChevron {
                // resizable + scaledToFit puts the glyph's ink in the middle of a
                // square, so rotating about the frame centre rotates about the ink
                Image(systemName: "chevron.right")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.snappy, value: isExpanded)
                    .frame(width: 44, height: 32, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleExpanded)
            }

        }
    }

    private func route(origin: String, destination: String, departure: Date, arrival: Date, isLead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(origin)
                Spacer(minLength: 12)
                Text(departure.formatted(Date.FormatStyle.dateTime.hour().minute()))
                    .monospacedDigit()
            }
            .animation(isLead ? nil : .snappy, value: isExpanded)
            HStack {
                Text(destination)
                Spacer(minLength: 12)
                Text(arrival.formatted(Date.FormatStyle.dateTime.hour().minute()))
                    .monospacedDigit()
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip(systemImage: "clock", text: journeyDuration(minutes: solution.durationMinutes))

            // the changes chip doubles as the expand/collapse target
            if solution.changeCount > 0 {
                chip(systemImage: "tram.fill", text: changesText)
                    .contentShape(Capsule())
                    .onTapGesture { if canExpand { onToggleExpanded() } }
            }

            Spacer(minLength: 0)

            if let price = solution.price {
                let tint = priceRank?.color ?? .secondary
                Text("\(solution.currency) \(price, format: .number.precision(.fractionLength(2)))")
                    .font(.footnote).fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .frame(height: Self.chipHeight)
                    .background(tint.opacity(0.15), in: Capsule())
            }
        }
    }

    private func chip(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.footnote).fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(height: Self.chipHeight)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    // MARK: - Actions

    private func minutesBetween(_ start: Date, _ end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start)) / 60)
    }

    private func segmentLabel(_ segment: SolutionSegment) -> String {
        if segment.isUntracked { return NSLocalizedString("Transfer", comment: "An urban transfer leg with no train number") }
        return segment.number.isEmpty ? NSLocalizedString("Bus", comment: "") : segment.number
    }

    private func segmentTint(_ segment: SolutionSegment) -> Color {
        if segment.isUntracked { return .secondary }
        return segment.isBus ? .blue : .primary
    }
}

