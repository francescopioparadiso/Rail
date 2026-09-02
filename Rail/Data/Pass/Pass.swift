import SwiftData
import Foundation

@Model
final class Pass {
    var id: UUID = UUID()
    
    var name: String = ""
    var start_date: Date = Date()
    var expiry_date: Date = Date()
    
    var is_principal: Bool = false
    var price: String = ""
    
    @Attribute(.externalStorage) var image: Data?
    /// The original ticket PDF from the confirmation email, kept for expense
    /// and tax paperwork. External storage so it syncs without bloating the record.
    @Attribute(.externalStorage) var pdf: Data?
    
    init(
        id: UUID,
        name: String,
        start_date: Date = Date(),
        expiry_date: Date,
        is_principal: Bool,
        price: String = "",
        image: Data? = nil,
        pdf: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.start_date = start_date
        self.expiry_date = expiry_date
        self.is_principal = is_principal
        self.price = price
        self.image = image
        self.pdf = pdf
    }
}
