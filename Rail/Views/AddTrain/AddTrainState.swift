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
    
    var title: String {
        switch self {
        case .addTrain:
            return NSLocalizedString("Add Train", comment: "")
        case .chooseTrain:
            return NSLocalizedString("Choose Train", comment: "")
        case .chooseStops:
            return NSLocalizedString("Choose Stops", comment: "")
        case .chooseDate:
            return NSLocalizedString("Choose Date", comment: "")
        }
    }
}

enum FetchState: CaseIterable {
    case idle
    case fetching
    case success
    case failure
    
    var title: String {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return NSLocalizedString("Searching solutions...", comment: "")
        case .failure:
            return NSLocalizedString("No solutions found", comment: "")
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
    
    var description: String {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return NSLocalizedString("This can take a few seconds.", comment: "")
        case .failure:
            return NSLocalizedString("Try checking the train number and your internet connection.", comment: "")
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
