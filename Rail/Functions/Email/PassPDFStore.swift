import Foundation

/// Holds pass PDFs on disk between fetching an email and importing the pass.
///
/// They can't ride along in `EmailPassContent`: that list is persisted inside
/// `UserProfile.emails` as plain Codable, with no external storage, so a few
/// hundred kilobytes per pass would bloat the record and risk CloudKit's limits.
/// Once a pass is imported the bytes move onto `Pass.pdf`, which does use
/// external storage and syncs properly, and the staged file is discarded.
/// Pure file IO, safe off the main actor during mailbox sync.
nonisolated enum PassPDFStore {
    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let folder = base.appending(path: "PendingPassPDFs", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Writes the PDF and returns the filename to remember it by.
    static func stage(_ data: Data) -> String? {
        guard !data.isEmpty, let directory else { return nil }
        let name = UUID().uuidString + ".pdf"
        do {
            try data.write(to: directory.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ filename: String?) -> Data? {
        guard let filename, let directory else { return nil }
        return try? Data(contentsOf: directory.appending(path: filename))
    }

    static func discard(_ filename: String?) {
        guard let filename, let directory else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }

    /// Drops staged files no longer referenced by any pending pass.
    static func prune(keeping filenames: Set<String>) {
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in contents where !filenames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }
}
