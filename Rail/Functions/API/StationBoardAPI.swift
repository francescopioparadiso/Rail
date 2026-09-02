import Foundation

/// Which side of a station's timetable is being read.
enum StationBoardKind: String, CaseIterable, Identifiable {
    case departures
    case arrivals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .departures: String(localized: "Departures")
        case .arrivals: String(localized: "Arrivals")
        }
    }
}

/// One train on a station's board.
struct BoardTrain: Identifiable, Hashable {
    /// The viaggiatreno identifier, "S01700/2239/1788300000000". It is exactly what
    /// `TrenitaliaAPI.info` takes, so opening a row resolves the whole journey
    /// without a second lookup.
    let id: String

    let logo: String
    let number: String

    /// Where it is bound for on a departures board, where it came from on an
    /// arrivals one — the one name that tells the trains on a board apart.
    let counterpart: String

    let scheduledTime: Date
    let delayMinutes: Int
    let platform: String
    let isCancelled: Bool

    /// When the train is actually expected here.
    var effectiveTime: Date {
        Calendar.current.date(byAdding: .minute, value: delayMinutes, to: scheduledTime) ?? scheduledTime
    }
}

/// The timetable viaggiatreno publishes for a single station: everything due
/// there over roughly the next two hours, arrivals and departures alike.
enum StationBoardAPI {

    // MARK: - Methods

    /// Stations whose name begins with `query`, carrying the `S`-prefixed codes the
    /// board endpoints take. The lefrecce autocomplete used to search journeys
    /// returns its own numeric ids, which the timetable does not accept.
    static func stations(matching query: String) async -> [StationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let encoded = trimmed.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/autocompletaStazione/\(encoded)")
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let body = String(data: data, encoding: .utf8) else { return [] }

            return body.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "|")
                guard parts.count == 2 else { return nil }
                let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                // Codes that don't start with S are places the boards don't serve.
                guard code.hasPrefix("S") else { return nil }
                return StationSuggestion(name: String(parts[0]).capitalized, code: code)
            }
        } catch {
            print("Error fetching station board suggestions: \(error)")
            return []
        }
    }

    /// Everything due at `code` around `date`, in the order it will actually
    /// call — a train running late takes its delayed place in the queue.
    static func board(_ kind: StationBoardKind, at code: String, on date: Date = Date()) async -> [BoardTrain] {
        let path = kind == .departures ? "partenze" : "arrivi"
        guard !code.isEmpty,
              let encodedMoment = boardTimestamp(date).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/\(path)/\(code)/\(encodedMoment)")
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return entries.compactMap { boardTrain(from: $0, kind: kind) }
                .sorted { $0.effectiveTime < $1.effectiveTime }
        } catch {
            print("Error fetching station board: \(error)")
            return []
        }
    }

    // MARK: - Helpers

    /// The endpoint wants a JavaScript `Date.toString()`, e.g.
    /// "Wed Sep 02 2026 18:54:00 UTC+0000". Anything else comes back empty.
    private static func boardTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'UTC+0000'"
        return formatter.string(from: date)
    }

    /// The badge to draw on the row.
    ///
    /// `categoria` comes back empty for the Frecce — their acronym lives only in the
    /// display name, " FR 9563", leading space and all — so the name is read first,
    /// the same way a journey's own logo is derived.
    private static func category(of entry: [String: Any]) -> String {
        let displayName = entry["compNumeroTreno"] as? String ?? ""
        if let acronym = displayName.split(separator: " ").first, !acronym.allSatisfy(\.isNumber) {
            return String(acronym)
        }
        return (entry["categoria"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func boardTrain(from entry: [String: Any], kind: StationBoardKind) -> BoardTrain? {
        guard let number = entry["numeroTreno"] as? Int,
              let origin = entry["codOrigine"] as? String,
              let departureDay = entry["dataPartenzaTreno"] as? Int else { return nil }

        // A board carries only the time for the side it is showing: a departures
        // row has no arrival, and an arrivals row no departure.
        let key = kind == .departures ? "orarioPartenza" : "orarioArrivo"
        guard let milliseconds = entry[key] as? Int, milliseconds > 0 else { return nil }

        let platform = kind == .departures
            ? entry["binarioEffettivoPartenzaDescrizione"] as? String ?? entry["binarioProgrammatoPartenzaDescrizione"] as? String
            : entry["binarioEffettivoArrivoDescrizione"] as? String ?? entry["binarioProgrammatoArrivoDescrizione"] as? String

        let counterpart = (kind == .departures ? entry["destinazione"] : entry["origine"]) as? String ?? ""

        return BoardTrain(
            id: "\(origin)/\(number)/\(departureDay)",
            logo: category(of: entry),
            number: String(number),
            counterpart: counterpart.capitalized,
            scheduledTime: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000),
            delayMinutes: entry["ritardo"] as? Int ?? 0,
            platform: platform.map { romanToArabic(platform: $0) } ?? "",
            isCancelled: (entry["provvedimento"] as? Int ?? 0) == 1
        )
    }
}
