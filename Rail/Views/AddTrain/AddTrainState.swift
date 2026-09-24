import SwiftUI

enum SearchType: String, CaseIterable {
    case number
    case stations
}

enum AddTrainStep: String, CaseIterable {
    case addTrain
    case chooseTrain
    case chooseStops
    case chooseDate
    
    /// Place in the flow, so moving between steps knows which way to slide.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// A key rather than a resolved string: `NSLocalizedString` reads the bundle's
    /// language and ignores `\.locale`, so a title resolved here stayed English
    /// however the surrounding view was configured.
    var title: LocalizedStringKey {
        switch self {
        case .addTrain: "Add Train"
        case .chooseTrain: "Choose Train"
        case .chooseStops: "Choose Stops"
        case .chooseDate: "Choose Date"
        }
    }
}

/// A move to another step, told apart from the last even when it's to the same one.
struct StepRequest: Equatable {
    let id = UUID()
    let step: AddTrainStep
}

/// One station field in a trip: the departure, a stop to spend time at, or
/// the arrival, depending on where it sits in the list.
struct StationEntry: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    /// The lefrecce location id, empty until a suggestion is picked.
    var code = ""
}

/// A station row on its way to a new place in the list.
struct StationDrag {
    let id: UUID
    /// Where the row was when the drag began.
    let startIndex: Int
    var translation: CGFloat

    /// Keeps the row under the finger as it's moved past its neighbours.
    func offset(at index: Int, rowHeight: CGFloat) -> CGFloat {
        translation - CGFloat(index - startIndex) * rowHeight
    }

    static func space(_ trip: Int) -> String { "stations-\(trip)" }
}

/// One train to pick in a search with stops or a return: from one station to the next.
struct JourneyLeg: Hashable {
    let origin: String
    let destination: String
    let originCode: String
    let destinationCode: String
    let date: Date
}

/// How a page of solutions is narrowed down, kept for each page so every one
/// comes back the way it was left.
struct SolutionListState: Hashable {
    var searchText = ""
    var filters = SolutionFilters()
    var sort: SolutionSort?
    var expandedID: UUID?
}

enum FetchState: CaseIterable {
    case idle
    case fetching
    case success
    case failure
    
    var title: LocalizedStringKey {
        switch self {
        case .idle, .success: ""
        case .fetching: "Searching solutions..."
        case .failure: "No solutions found"
        }
    }
    
    var icon: String {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return "text.magnifyingglass"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return "This can take a few seconds."
        case .failure:
            return "Try checking the train number and your internet connection."
        }
    }
    
    var color: Color {
        switch self {
        case .idle, .success:
            return Color.primary
        case .fetching:
            return Color.secondary
        case .failure:
            return Color.red
        }
    }
}
