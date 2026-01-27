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
