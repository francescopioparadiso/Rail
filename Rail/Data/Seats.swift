import SwiftData
import Foundation

@Model
final class Seat {
    var id: UUID = UUID()
    var trainID: UUID = UUID()
    
    var name: String = ""
    
    var carriage: String = ""
    var number: String = ""
    
    // ✅ CHANGED: External storage allows CloudKit to sync images efficiently
    // We use Data? (optional) so seats without images don't take up space
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
