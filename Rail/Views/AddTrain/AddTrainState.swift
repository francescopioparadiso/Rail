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
