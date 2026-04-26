import SwiftData
import Foundation

@Model
final class Train {
    var id: UUID = UUID()
    
    var logo: String = ""
    var number: String = ""
    var identifier: String = ""
    var provider: String = ""

    var last_update_time: Date = Date()
    var delay: Int = 0
    var direction: String = ""

    var issue: String = ""

    init(id: UUID, logo: String, number: String, identifier: String, provider: String, last_update_time: Date, delay: Int, direction: String, issue: String) {
        self.id = id
        self.logo = logo
        self.number = number
        self.identifier = identifier
        self.provider = provider
        self.last_update_time = last_update_time
        self.delay = delay
        self.direction = direction
        self.issue = issue
    }
}

struct StopSummary {
    let first: Stop
    let last: Stop
    let firstNoIssues: Stop
    let lastNoIssues: Stop
    
    static func calculate(for trainID: UUID, in allStops: [Stop]) -> StopSummary {
        let trainStops = allStops
            .filter { $0.id == trainID }
            .sorted(by: { $0.ref_time < $1.ref_time })
        
        let selectedStops = trainStops.filter { $0.is_selected }
        let selectedNoIssues = selectedStops.filter { $0.status != 3 }
        
        let first = selectedStops.first ?? trainStops.first ?? Stop.placeholder()
        let last = selectedStops.last ?? Stop.placeholder()
        let firstNoIssues = selectedNoIssues.first ?? selectedStops.first ?? trainStops.first ?? Stop.placeholder()
        let lastNoIssues = selectedNoIssues.last ?? selectedStops.last ?? Stop.placeholder()
        
        return StopSummary(
            first: first,
            last: last,
            firstNoIssues: firstNoIssues,
            lastNoIssues: lastNoIssues
        )
    }
}
