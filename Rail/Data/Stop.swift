import SwiftData
import Foundation

@Model
final class Stop {
    var id: UUID = UUID()

    var name: String = ""
    var platform: String = ""
    var weather: String = ""
    
    var is_selected: Bool = false
    var status: Int = 0
    var is_completed: Bool = false
    var is_in_station: Bool = false

    var dep_delay: Int = 0
    var arr_delay: Int = 0

    var dep_time_id: Date = Date()
    var arr_time_id: Date = Date()
    var dep_time_eff: Date = Date()
    var arr_time_eff: Date = Date()
    var ref_time: Date = Date()
    
    init(id: UUID,
         name: String,
         platform: String,
         weather: String,
         is_selected: Bool,
         status: Int,
         is_completed: Bool,
         is_in_station: Bool,
         dep_delay: Int,
         arr_delay: Int,
         dep_time_id: Date,
         arr_time_id: Date,
         dep_time_eff: Date,
         arr_time_eff: Date,
         ref_time: Date
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.weather = weather
        self.is_selected = is_selected
        self.status = status
        self.is_completed = is_completed
        self.is_in_station = is_in_station
        self.dep_delay = dep_delay
        self.arr_delay = arr_delay
        self.dep_time_id = dep_time_id
        self.arr_time_id = arr_time_id
        self.dep_time_eff = dep_time_eff
        self.arr_time_eff = arr_time_eff
        self.ref_time = ref_time
    }
}
