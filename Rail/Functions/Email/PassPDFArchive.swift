import Foundation

/// Bundles several pass PDFs into one zip for sharing.
///
/// Foundation has no zip API, but `NSFileCoordinator`'s `.forUploading` option
/// hands back a zipped copy of a directory — the supported way to do this
/// without pulling in a compression library.
enum PassPDFArchive {
    struct Result {
        let url: URL
        /// Passes that had no stored PDF and so aren't in the archive.
        let skipped: [String]
    }

    static func makeArchive(from passes: [Pass]) throws -> Result {
        // The coordinator names the archive's inner folder after the directory it
        // zips, so that directory gets the friendly name and a throwaway UUID
        // parent keeps concurrent shares from colliding.
        let folderName = archiveBaseName()
        let root = URL.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let staging = root.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var used: Set<String> = []
        var skipped: [String] = []

        for pass in passes.sorted(by: { $0.start_date < $1.start_date }) {
            guard let pdf = pass.pdf, !pdf.isEmpty else {
                skipped.append(pass.name)
                continue
            }
            try pdf.write(to: staging.appending(path: uniqueName(for: pass, taken: &used)), options: .atomic)
        }

        guard !used.isEmpty else { throw ArchiveError.nothingToArchive }

        var coordinatorError: NSError?
        var archived: URL?
        var copyError: Error?

        NSFileCoordinator().coordinate(readingItemAt: staging, options: [.forUploading], error: &coordinatorError) { zipped in
            let destination = URL.temporaryDirectory.appending(path: folderName + ".zip")
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
                archived = destination
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard let archived else { throw ArchiveError.nothingToArchive }
        return Result(url: archived, skipped: skipped)
    }

    enum ArchiveError: LocalizedError {
        case nothingToArchive
        var errorDescription: String? {
            String(localized: "None of the selected passes has a PDF to share.")
        }
    }

    /// "2026_07.pdf" or "2026_07_01-2026_07_15.pdf", de-duplicated.
    private static func uniqueName(for pass: Pass, taken: inout Set<String>) -> String {
        let base = pass.documentBaseName
        var candidate = base + ".pdf"
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(base) (\(suffix)).pdf"
            suffix += 1
        }
        taken.insert(candidate)
        return candidate
    }

    private static func archiveBaseName() -> String {
        let stamp = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
            .replacingOccurrences(of: "/", with: "-")
        return "\(String(localized: "Passes")) \(stamp)"
    }
}
