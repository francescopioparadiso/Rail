import Foundation

struct FetchedPassEmail: Sendable {
    /// Filename of the source PDF staged by `PassPDFStore`, if it was kept.
    let imapUID: String
    let date: Date
    let name: String
    let startDate: Date
    let endDate: Date
    let qrcode: Data
    let price: String
    var pdfFilename: String? = nil
}

struct EmailPassFetchResult: Sendable {
    let passes: [FetchedPassEmail]
    let failedUIDs: [UInt64]
    let warnings: [String]
    let highestUID: UInt64?
    let uidValidity: UInt64?
    let didResetUIDValidity: Bool
    let foundCount: Int
}

actor EmailPassFetcher {

    // MARK: - Properties

    private let session: IMAPSession

    init(account: Emails) {
        self.session = IMAPSession(account: account)
    }

    
    
    

    

    /// Connects and opens INBOX to confirm email + app password work for fetching.
    

    

    /// Search webmaster@trenitalia.it emails for Abbonamento PDFs and parse pass details.
    /// Mirrors Sketch/Scripts/pass_fetcher.py (Gmail All Mail + TEXT Abbonamento).
    func fetchPassEmails(
        afterUID: UInt64?,
        expectedUIDValidity: UInt64?,
        retryUIDs: [UInt64],
        progress: (@MainActor @Sendable (EmailFetchProgress) -> Void)? = nil
    ) async throws -> EmailPassFetchResult {
        try Task.checkCancellation()
        session.useLargeMessageLimits(true)
        defer {
            session.useLargeMessageLimits(false)
        }

        let (mailbox, passFolder) = try await session.openPassMailbox()
        defer { session.close() }

        let currentUIDValidity = IMAPResponse.uidValidity(in: mailbox)
        let didResetUIDValidity = expectedUIDValidity != nil
            && currentUIDValidity != nil
            && expectedUIDValidity != currentUIDValidity
        let effectiveLastUID = didResetUIDValidity ? nil : afterUID
        let uidConstraint: String
        if let effectiveLastUID, effectiveLastUID < UInt64.max {
            uidConstraint = "UID \(effectiveLastUID + 1):*"
        } else if effectiveLastUID == UInt64.max {
            uidConstraint = "UID \(UInt64.max):\(UInt64.max)"
        } else {
            uidConstraint = ""
        }

        // Subject is often "Il Tuo Biglietto Trenitalia"; "Abbonamento" lives in the body/PDF.
        let criteriaOptions = [
            #"FROM "webmaster@trenitalia.it" TEXT "Abbonamento""#,
            #"FROM "webmaster@trenitalia.it" TEXT "Codice Abbonamento""#,
            #"FROM "webmaster@trenitalia.it""#
        ]
        var search = ""
        var trustAbbonamentoSearch = false
        for (criteriaIndex, criteria) in criteriaOptions.enumerated() {
            let commandText = uidConstraint.isEmpty
                ? "UID SEARCH \(criteria)"
                : "UID SEARCH \(uidConstraint) \(criteria)"
            do {
                let response = try await session.command(commandText)
                if IMAPResponse.taggedSuccess(response) {
                    search = response
                    trustAbbonamentoSearch = criteriaIndex < 2
                    break
                }
            } catch {
                continue
            }
        }
        guard !search.isEmpty else { throw EmailFetchError.searchFailed }

        let newUIDs = IMAPResponse.uids(in: search)
            .compactMap { uid in UInt64(uid).map { (raw: uid, numeric: $0) } }
            .filter { item in
                guard let effectiveLastUID else { return true }
                return item.numeric > effectiveLastUID
            }
            .sorted { $0.numeric < $1.numeric }
        let retryValues = didResetUIDValidity ? [] : retryUIDs
        var uidsByValue = Dictionary(uniqueKeysWithValues: newUIDs.map { ($0.numeric, $0) })
        for uid in retryValues {
            uidsByValue[uid] = (raw: String(uid), numeric: uid)
        }
        // Newest first so recent passes appear quickly.
        let matchingUIDs = uidsByValue.values.sorted { $0.numeric > $1.numeric }
        await progress?(
            EmailFetchProgress(found: matchingUIDs.count, processed: 0, skipped: 0, latestWarning: nil)
        )

        var passes: [FetchedPassEmail] = []
        var failedUIDs: [UInt64] = []
        var warnings: [String] = []
        var seenFingerprints = Set<String>()
        var highestProcessedUID = effectiveLastUID

        for (index, uid) in matchingUIDs.enumerated() {
            try Task.checkCancellation()
            var latestWarning: String?
            do {
                let raw = try await session.command("UID FETCH \(uid.raw) (BODY.PEEK[])")
                guard IMAPResponse.taggedSuccess(raw) else { throw EmailFetchError.fetchFailed }

                let parsedPasses = parsePassEmails(
                    raw,
                    uid: uid.raw,
                    trustAbbonamentoSearch: trustAbbonamentoSearch
                )
                if parsedPasses.isEmpty {
                    if trustAbbonamentoSearch {
                        // Soft failure: Abbonamento hit but no usable PDF — keep for retry.
                        failedUIDs.append(uid.numeric)
                        let warning = String(localized: "Skipped pass email \(uid.raw): could not parse PDF")
                        latestWarning = warning
                        warnings.append(warning)
                    }
                    // FROM-only search can include normal tickets; don't treat as failures.
                } else {
                    for parsed in parsedPasses {
                        let fingerprint = "\(parsed.name)|\(parsed.startDate.timeIntervalSince1970)|\(parsed.endDate.timeIntervalSince1970)"
                        guard seenFingerprints.insert(fingerprint).inserted else { continue }
                        passes.append(parsed)
                    }
                    highestProcessedUID = max(highestProcessedUID ?? 0, uid.numeric)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedUIDs.append(uid.numeric)
                let warning = String(
                    localized: "Skipped pass email \(uid.raw): \(error.localizedDescription)"
                )
                latestWarning = warning
                warnings.append(warning)
                session.close()

                if index < matchingUIDs.count - 1 {
                    do {
                        _ = try await session.openMailbox(folder: passFolder)
                    } catch {
                        let remaining = matchingUIDs[(index + 1)...].map(\.numeric)
                        failedUIDs.append(contentsOf: remaining)
                        let reconnectWarning = String(
                            localized: "Could not reconnect to continue scanning: \(error.localizedDescription)"
                        )
                        warnings.append(reconnectWarning)
                        await progress?(
                            EmailFetchProgress(
                                found: matchingUIDs.count,
                                processed: matchingUIDs.count,
                                skipped: failedUIDs.count,
                                latestWarning: reconnectWarning
                            )
                        )
                        break
                    }
                }
            }
            await progress?(
                EmailFetchProgress(
                    found: matchingUIDs.count,
                    processed: index + 1,
                    skipped: failedUIDs.count,
                    latestWarning: latestWarning
                )
            )
        }

        // Don't advance the UID cursor past soft/network failures or they never retry.
        let safeHighestUID: UInt64?
        if failedUIDs.isEmpty {
            safeHighestUID = newUIDs.last?.numeric ?? effectiveLastUID
        } else {
            safeHighestUID = highestProcessedUID
        }

        return EmailPassFetchResult(
            passes: passes.sorted {
                if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
                return $0.date > $1.date
            },
            failedUIDs: Array(Set(failedUIDs)).sorted(),
            warnings: warnings,
            highestUID: safeHighestUID,
            uidValidity: currentUIDValidity,
            didResetUIDValidity: didResetUIDValidity,
            foundCount: matchingUIDs.count
        )
    }

    private func parsePassEmails(
        _ raw: String,
        uid: String,
        trustAbbonamentoSearch: Bool
    ) -> [FetchedPassEmail] {
        let searchable = IMAPResponse.messageContent(from: raw) ?? raw
        let decoded = EmailBodyDecoder.unescapeQuotedPrintable(searchable)
            + "\n"
            + EmailBodyDecoder.unescapeQuotedPrintable(raw)

        guard let from = IMAPResponse.header("From", in: searchable)
                ?? IMAPResponse.header("From", in: raw)
                ?? IMAPResponse.header("FROM", in: searchable)
                ?? IMAPResponse.header("FROM", in: raw) else { return [] }

        let sender = from.firstIndex(of: "<").flatMap { s in
            from.firstIndex(of: ">").map { String(from[from.index(after: s)..<$0]).lowercased() }
        } ?? from.lowercased()

        guard sender.contains("webmaster@trenitalia.it") || sender.contains("trenitalia.it") else {
            return []
        }

        let subject = IMAPResponse.header("Subject", in: searchable)
            ?? IMAPResponse.header("Subject", in: raw)
            ?? IMAPResponse.header("SUBJECT", in: searchable)
            ?? ""
        let haystack = (subject + "\n" + decoded).lowercased()
        let pdfs = EmailMIMEExtractor.pdfAttachments(from: searchable)
            + EmailMIMEExtractor.pdfAttachments(from: raw)

        // Gmail TEXT "Abbonamento" often matches PDF attachment content that never appears
        // in the HTML part — still try PDFs when the search already required Abbonamento.
        if !trustAbbonamentoSearch && !haystack.contains("abbonamento") {
            return []
        }

        let date = IMAPResponse.header("Date", in: searchable).flatMap(IMAPResponse.parseDate)
            ?? IMAPResponse.header("Date", in: raw).flatMap(IMAPResponse.parseDate)
            ?? .distantPast

        var uniquePDFs: [Data] = []
        var seen = Set<Int>()
        for pdf in pdfs {
            let hash = pdf.hashValue
            if seen.insert(hash).inserted {
                uniquePDFs.append(pdf)
            }
        }

        var results: [FetchedPassEmail] = []
        for pdf in uniquePDFs {
            guard let parsed = PassPDFParser.parse(pdfData: pdf) else { continue }
            results.append(
                FetchedPassEmail(
                    imapUID: uid,
                    date: date,
                    name: parsed.name,
                    startDate: parsed.startDate,
                    endDate: parsed.endDate,
                    qrcode: parsed.qrImageData,
                    price: parsed.price,
                    pdfFilename: PassPDFStore.stage(pdf)
                )
            )
        }
        return results
    }
}
