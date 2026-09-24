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

    private var changesText: LocalizedStringKey {
        "\(solution.changeCount) changes"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The first leg's header and route stay put across expansion — only
            // their values change — so nothing above the fold shifts or refades.
            if let first = solution.segments.first {
                VStack(alignment: .leading, spacing: 12) {
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

                    // Collapsed these sum up the whole trip; expanded they become the
                    // first train's own, and each leg below gets its own.
                    chips(
                        minutes: isExpanded ? minutesBetween(first.departureTime, first.arrivalTime) : solution.durationMinutes,
                        showsChanges: !isExpanded,
                        price: isExpanded ? solution.ticketFares[0] : solution.price
                    )
                }
            }

            // Remaining legs fade in where they'll sit while the row grows to
            // make room for them. Clipped, so they're only ever seen inside the
            // room the row has made so far.
            VStack(spacing: 0) {
                // a single train has nothing below it, not even the gap
                if isExpanded && canExpand {
                    remainingLegs
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
        }
        .fontDesign(appFontDesign)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private var remainingLegs: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    chips(
                        minutes: minutesBetween(segment.departureTime, segment.arrivalTime),
                        showsChanges: false,
                        price: solution.ticketFares[index]
                    )
                }
            }
        }
    }

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
            .animation(isLead ? nil : .smooth, value: isExpanded)

            segmentLabel(segment)
                .font(.headline).fontWeight(.semibold)
                .foregroundStyle(segmentTint(segment))
                .lineLimit(1)
                .animation(isLead ? nil : .smooth, value: isExpanded)

            if extraCount > 0 && !isExpanded {
                Text("+\(extraCount)")
                    .font(.body).fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
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
                    .animation(.smooth, value: isExpanded)
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
            .animation(isLead ? nil : .smooth, value: isExpanded)
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

    private func chips(minutes: Int, showsChanges: Bool, price: Double?) -> some View {
        HStack(spacing: 8) {
            chip(systemImage: "clock", text: Text(verbatim: journeyDuration(minutes: minutes)))

            // the changes chip doubles as the expand target
            if showsChanges && solution.changeCount > 0 {
                chip(systemImage: "tram.fill", text: Text(changesText))
                    .contentShape(Capsule())
                    .onTapGesture { if canExpand { onToggleExpanded() } }
            }

            Spacer(minLength: 0)

            if let price {
                // the rank is for the whole fare, so a ticket that's only part
                // of it stays neutral
                let tint = price == solution.price ? priceRank?.color ?? .secondary : .secondary
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
        // chips just swap, with no animation: easing them looked like they
        // slid in while the row grew around them
        .transaction { $0.animation = nil }
    }

    private func chip(systemImage: String, text: Text) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            text
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

    private func segmentLabel(_ segment: SolutionSegment) -> Text {
        if segment.isUntracked { return Text("Transfer") }
        return segment.number.isEmpty ? Text("Bus") : Text(verbatim: segment.number)
    }

    private func segmentTint(_ segment: SolutionSegment) -> Color {
        if segment.isUntracked { return .secondary }
        return segment.isBus ? .blue : .primary
    }
}
