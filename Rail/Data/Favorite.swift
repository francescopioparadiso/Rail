import SwiftData
import Foundation

@Model
final class Favorite {
    var id: UUID = UUID()
    
    var index: Int = 0
    
    var identifier: String = ""
    var provider: String = ""
    var logo: String = ""
    var number: String = ""
    
    var stop_names: [String] = []
    var stop_ref_times: [Date] = []
    
    init(id: UUID, index: Int, identifier: String, provider: String, logo: String, number: String, stop_names: [String], stop_ref_times: [Date]) {
        self.id = id
        self.index = index
        self.identifier = identifier
        self.provider = provider
        self.logo = logo
        self.number = number
        self.stop_names = stop_names
        self.stop_ref_times = stop_ref_times
    }
}
