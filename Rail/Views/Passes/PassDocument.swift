import SwiftUI
import UniformTypeIdentifiers

/// Wraps a pass PDF so ShareLink hands other apps a real file rather than raw
/// bytes — Mail, Files and AirDrop all need something with a name and a type.
struct PassDocument: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            document.data
        }
        .suggestedFileName { $0.filename }
    }
}
