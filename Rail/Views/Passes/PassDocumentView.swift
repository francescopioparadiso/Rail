import SwiftUI
import PDFKit

/// Reads a stored pass PDF without leaving the app.
struct PassDocumentView: View {
    // MARK: - Properties

    let data: Data
    let filename: String

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            PDFDocumentView(data: data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: PassDocument(data: data, filename: filename),
                                  preview: SharePreview(filename)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .fontDesign(appFontDesign)
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil { view.document = PDFDocument(data: data) }
    }
}

/// Identifies a document so it can drive a `.sheet(item:)`.
struct PassDocumentPreview: Identifiable {
    let data: Data
    let filename: String
    var id: String { filename }
}
