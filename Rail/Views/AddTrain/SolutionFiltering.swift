import Foundation

// MARK: - Sorting

enum SolutionSortField: Hashable {
    case duration, price

    var icon: String {
        switch self {
        case .duration: return "clock"
        case .price: return "eurosign"
        }
    }
}

/// Tapping a field cycles ascending → descending → off.
struct SolutionSort: Hashable {
    let field: SolutionSortField
    var isAscending: Bool

    var icon: String { isAscending ? "arrow.down" : "arrow.up" }
}

// MARK: - Filtering

/// A range bucket over duration (minutes) or price (currency units).
struct SolutionBucket: Identifiable, Hashable {
    let id: Int
    /// Exclusive lower bound; nil for the first bucket.
    let lowerBound: Double?
    /// Inclusive upper bound; nil for the last bucket.
    let upperBound: Double?

    func contains(_ value: Double) -> Bool {
        if let lower = lowerBound, value <= lower { return false }
        if let upper = upperBound, value > upper { return false }
        return true
    }
}

struct SolutionFilters: Hashable {
    /// Number of changes; 3 stands for "3 or more".
    var changes: Set<Int> = []
    var durationBuckets: Set<Int> = []
    var priceBuckets: Set<Int> = []

    var isActive: Bool { !changes.isEmpty || !durationBuckets.isEmpty || !priceBuckets.isEmpty }
}

// MARK: - Facets derived from the current results

/// The filter options actually worth offering for a given set of solutions:
/// only the change counts that occur, and range buckets sized from the data.
struct SolutionFacets {
    let changeOptions: [Int]
    let durationBuckets: [SolutionBucket]
    let priceBuckets: [SolutionBucket]

    var isEmpty: Bool { changeOptions.count < 2 && durationBuckets.isEmpty && priceBuckets.isEmpty }

    init(solutions: [Solution]) {
        changeOptions = Set(solutions.map { min($0.changeCount, 3) }).sorted()
        durationBuckets = SolutionFacets.buckets(
            for: solutions.map { Double($0.durationMinutes) },
            step: 5
        )
        let prices = solutions.compactMap(\.price)
        priceBuckets = SolutionFacets.buckets(
            for: prices,
            step: (prices.max() ?? 0) - (prices.min() ?? 0) >= 20 ? 5 : 1
        )
    }

    /// Splits the values into three roughly equal groups, then rounds the two
    /// boundaries to a friendly step — nudging them until every bucket still
    /// holds something, so no option is offered that can only ever show zero.
    static func buckets(for values: [Double], step: Double) -> [SolutionBucket] {
        let sorted = values.sorted()
        guard sorted.count >= 3, let low = sorted.first, let high = sorted.last, low < high else { return [] }

        let raw = [sorted[sorted.count / 3], sorted[2 * sorted.count / 3]]
        var bounds: [Double] = []
        for candidate in raw {
            var rounded = (candidate / step).rounded() * step
            // keep the boundary strictly inside the range so no bucket empties
            if rounded <= low { rounded = (low / step).rounded(.down) * step + step }
            if rounded >= high { rounded = (high / step).rounded(.up) * step - step }
            if rounded > low, rounded < high, !bounds.contains(rounded) { bounds.append(rounded) }
        }
        bounds.sort()

        guard let first = bounds.first else { return [] }
        if bounds.count == 1 {
            return [
                SolutionBucket(id: 0, lowerBound: nil, upperBound: first),
                SolutionBucket(id: 1, lowerBound: first, upperBound: nil),
            ]
        }
        return [
            SolutionBucket(id: 0, lowerBound: nil, upperBound: first),
            SolutionBucket(id: 1, lowerBound: first, upperBound: bounds[1]),
            SolutionBucket(id: 2, lowerBound: bounds[1], upperBound: nil),
        ]
    }
}

// MARK: - Applying search, filters and sort

enum SolutionQuery {
    static func apply(
        to solutions: [Solution],
        searchText: String,
        filters: SolutionFilters,
        facets: SolutionFacets,
        sort: SolutionSort?
    ) -> [Solution] {
        var result = solutions.filter { matches($0, searchText: searchText) }
        result = result.filter { passes($0, filters: filters, facets: facets) }

        guard let sort else { return result }
        return result.sorted { lhs, rhs in
            let ordered: Bool
            switch sort.field {
            case .duration:
                ordered = lhs.durationMinutes == rhs.durationMinutes
                    ? lhs.departureTime < rhs.departureTime
                    : lhs.durationMinutes < rhs.durationMinutes
            case .price:
                // solutions without a fare sink to the bottom either way
                let left = lhs.price ?? .greatestFiniteMagnitude
                let right = rhs.price ?? .greatestFiniteMagnitude
                ordered = left == right ? lhs.departureTime < rhs.departureTime : left < right
            }
            return sort.isAscending ? ordered : !ordered
        }
    }

    static func passes(_ solution: Solution, filters: SolutionFilters, facets: SolutionFacets) -> Bool {
        if !filters.changes.isEmpty, !filters.changes.contains(min(solution.changeCount, 3)) {
            return false
        }
        if !filters.durationBuckets.isEmpty {
            let minutes = Double(solution.durationMinutes)
            let hit = facets.durationBuckets.contains { filters.durationBuckets.contains($0.id) && $0.contains(minutes) }
            if !hit { return false }
        }
        if !filters.priceBuckets.isEmpty {
            guard let price = solution.price else { return false }
            let hit = facets.priceBuckets.contains { filters.priceBuckets.contains($0.id) && $0.contains(price) }
            if !hit { return false }
        }
        return true
    }

    /// Substring match over stations, train numbers, times, duration and fare.
    static func matches(_ solution: Solution, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        var haystack: [String] = [
            journeyDuration(minutes: solution.durationMinutes),
            solution.departureTime.formatted(Date.FormatStyle.dateTime.hour().minute()),
            solution.arrivalTime.formatted(Date.FormatStyle.dateTime.hour().minute()),
        ]

        if let price = solution.price {
            haystack.append(String(format: "%.2f", price))
            haystack.append(String(format: "%.2f", price).replacingOccurrences(of: ".", with: ","))
            haystack.append("\(solution.currency)\(String(format: "%.2f", price))")
        }

        for segment in solution.segments {
            haystack.append(segment.origin)
            haystack.append(segment.destination)
            haystack.append(segment.number)
            haystack.append(segment.logo)
            haystack.append(segment.departureTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
            haystack.append(segment.arrivalTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
        }

        return haystack.contains { $0.lowercased().contains(query) }
    }
}

// MARK: - Option labels

func changeCountLabel(_ option: Int) -> String {
    option >= 3
        ? NSLocalizedString("3+ changes", comment: "Filter option for three or more changes")
        : String.localizedStringWithFormat(NSLocalizedString("%lld changes", comment: ""), option)
}

extension SolutionBucket {
    var durationLabel: String {
        rangeLabel(
            lower: lowerBound.map { journeyDuration(minutes: Int($0)) },
            upper: upperBound.map { journeyDuration(minutes: Int($0)) }
        )
    }

    func priceLabel(currency: String) -> String {
        let money: (Double) -> String = { "\(currency) \($0.formatted(.number.precision(.fractionLength(0))))" }
        return rangeLabel(lower: lowerBound.map(money), upper: upperBound.map(money))
    }
}

private func rangeLabel(lower: String?, upper: String?) -> String {
    switch (lower, upper) {
    case let (nil, upper?):
        return String(format: NSLocalizedString("Up to %@", comment: "Upper-bounded filter range"), upper)
    case let (lower?, upper?):
        return String(format: NSLocalizedString("%@ to %@", comment: "Filter range"), lower, upper)
    case let (lower?, nil):
        return String(format: NSLocalizedString("Over %@", comment: "Lower-bounded filter range"), lower)
    default:
        return ""
    }
}
