import SwiftData
import Foundation

@Model
final class Seat {
    var id: UUID = UUID()
    var trainID: UUID = UUID()
    
    var name: String = ""
    
    var carriage: String = ""
    var number: String = ""
    
    @Attribute(.externalStorage) var image: Data?
    
    init(id: UUID, trainID: UUID, name: String, carriage: String, number: String, image: Data? = nil) {
        self.id = id
        self.trainID = trainID
        self.name = name
        self.carriage = carriage
        self.number = number
        self.image = image
    }
}
