import SwiftData
import Foundation

@Model
final class Pass {
    var id: UUID = UUID()
    
    var name: String = ""
    var expiry_date: Date = Date()
    
    var is_principal: Bool = false
    
    @Attribute(.externalStorage) var image: Data?
    
    init(id: UUID, name: String, expiry_date: Date, is_principal: Bool, image: Data? = nil) {
        self.id = id
        self.name = name
        self.expiry_date = expiry_date
        self.is_principal = is_principal
        self.image = image
    }
}
