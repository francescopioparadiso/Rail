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

    // MARK: - Computed

    /// `price` as a number, or nil when it holds no amount.
    ///
    /// The stored text arrives in two shapes: the PDF parser writes `"62.00 €"`
    /// while the form's placeholder invites `"50,00 €"`, and either may carry a
    /// thousands separator. Whichever separator comes last is the decimal one.
    var priceValue: Double? {
        let digits = price.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !digits.isEmpty else { return nil }

        let lastComma = digits.lastIndex(of: ",")
        let lastDot = digits.lastIndex(of: ".")

        let normalized: String
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // both present: the later one is the decimal point, the other groups
            let decimal = comma > dot ? "," : "."
            let grouping = comma > dot ? "." : ","
            normalized = digits
                .replacingOccurrences(of: grouping, with: "")
                .replacingOccurrences(of: decimal, with: ".")
        case let (comma?, nil):
            // a lone comma separates decimals only when two digits follow it
            let decimals = digits.distance(from: digits.index(after: comma), to: digits.endIndex)
            normalized = decimals == 2
                ? digits.replacingOccurrences(of: ",", with: ".")
                : digits.replacingOccurrences(of: ",", with: "")
        case let (nil, dot?):
            let decimals = digits.distance(from: digits.index(after: dot), to: digits.endIndex)
            normalized = decimals == 2 ? digits : digits.replacingOccurrences(of: ".", with: "")
        case (nil, nil):
            normalized = digits
        }

        return Double(normalized)
    }
}
