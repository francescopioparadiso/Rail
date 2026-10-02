import Foundation

/// One stop of a scheduled Italo run.
struct ItaloScheduledCall {
    let code: String
    let arrival: Date
    let departure: Date
}

/// A direct Italo train as the ticket-booking site timetables it on one day.
struct ItaloScheduledRun {
    let number: String
    let calls: [ItaloScheduledCall]
}

/// Italo's live feed only knows a train from shortly before it leaves. Its booking
/// site sells tickets months ahead, so it knows every run's timetable: searching
/// a pair of stations there, as a guest, lists the direct trains with each stop.
extension ItaloAPI {
    private static let bookingSite = "https://biglietti.italotreno.com"
    private static let bookingAPI = "https://api-biglietti.italotreno.com/api/v1"

    // MARK: - Lookups

    static func station(code: String) -> ItaloStation? {
        stations.first { $0.code == code }
    }

    /// The station going by `name`, in either of the names Italo gives it or the
    /// one the rest of the app prints.
    static func station(named name: String) -> ItaloStation? {
        let target = comparable(name)
        guard !target.isEmpty else { return nil }
        return stations.first { comparable($0.name) == target || comparable($0.routeName) == target }
    }

    // MARK: - Timetable

    /// The direct Italo trains running from `origin` to `destination` on `day`,
    /// with the stops they make in between.
    static func scheduledRuns(from origin: ItaloStation, to destination: ItaloStation, on day: Date) async -> [ItaloScheduledRun] {
        guard origin != destination else { return [] }
        return await ScheduleCache.shared.runs(from: origin, to: destination, on: day)
    }

    /// `number`'s run on `day` between the two stations, in the shape the rest of
    /// the app reads a train in. Nothing is known yet about where it is or how late
    /// it runs; the live feed takes over on the day.
    static func scheduledInfo(number: String, from origin: ItaloStation, to destination: ItaloStation, on day: Date) async -> [String: Any]? {
        let runs = await scheduledRuns(from: origin, to: destination, on: day)
        guard let run = runs.first(where: { $0.number == number }) else { return nil }
        return info(for: run)
    }

    static func info(for run: ItaloScheduledRun) -> [String: Any] {
        let stops: [[String: Any]] = run.calls.enumerated().map { index, call in
            let reference = index == 0 ? call.departure : call.arrival
            return [
                "name": station(code: call.code)?.name ?? call.code,
                "platform": "-",
                "weather": "",
                "status": 0,
                "is_completed": false,
                "is_in_station": false,
                "dep_delay": 0,
                "arr_delay": 0,
                "dep_time_id": call.departure,
                "arr_time_id": call.arrival,
                "dep_time_eff": call.departure,
                "arr_time_eff": call.arrival,
                "ref_time": reference
            ]
        }

        return [
            "logo": "ITALO",
            "number": run.number,
            "identifier": run.number,
            "provider": "italo",
            // never updated, so the first refresh on the day goes ahead
            "last_update_time": Date.distantPast,
            "delay": 0,
            "direction": "",
            "issue": "",
            "stops": stops
        ]
    }

    // MARK: - Search

    fileprivate static func search(from origin: ItaloStation, to destination: ItaloStation, on day: Date) async -> [ItaloScheduledRun] {
        guard let token = await BookingSession.shared.token(),
              let url = URL(string: "\(bookingAPI)/booking") else { return [] }

        let body: [String: Any] = [
            "isRoundTrip": false,
            "departureStation": origin.code,
            "arrivalStation": destination.code,
            "departureDate": dayFormatter.string(from: day),
            "culture": "it-IT",
            "showPrivateOffers": false,
            "showBestPrices": false,
            "adultPassengers": 1,
            "youngPassengers": 0,
            "childPassengers": 0,
            "seniorPassengers": 0
        ]

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return [] }

            if status == 200 { return runs(in: data) }
            guard status == 202,
                  let accepted = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let operation = accepted["operationId"] as? String else { return [] }

            return await poll(operation: operation, token: token, after: accepted["pollAfter"] as? Int ?? 1500)
        } catch {
            print("Error searching Italo timetable: \(error)")
            return []
        }
    }

    /// The search runs on the server and answers 202 until it is done.
    private static func poll(operation: String, token: String, after delay: Int) async -> [ItaloScheduledRun] {
        guard let url = URL(string: "\(bookingAPI)/booking/status/\(operation)") else { return [] }

        var wait = delay
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: UInt64(max(wait, 500)) * 1_000_000)
            if Task.isCancelled { return [] }

            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { return [] }
                if status == 200 { return runs(in: data) }
                guard status == 202 else { return [] }
                let pending = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                wait = pending?["retryAfter"] as? Int ?? 1500
            } catch {
                print("Error polling Italo timetable: \(error)")
                return []
            }
        }
        return []
    }

    private static func runs(in data: Data) -> [ItaloScheduledRun] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trips = json["trips"] as? [[String: Any]] else { return [] }

        var runs: [ItaloScheduledRun] = []
        var seen: Set<String> = []

        for solution in trips.flatMap({ $0["travelSolutions"] as? [[String: Any]] ?? [] }) {
            // only trains that go straight there; the journey search joins the rest
            guard let journeys = solution["journeys"] as? [[String: Any]], journeys.count == 1,
                  journeys[0]["serviceProvider"] as? String == "ITALO",
                  let segments = journeys[0]["segments"] as? [[String: Any]], segments.count == 1,
                  let segment = segments.first,
                  let number = segment["trainNumber"] as? String, seen.insert(number).inserted,
                  let legs = segment["legs"] as? [[String: Any]], let first = legs.first else { continue }

            var calls: [ItaloScheduledCall] = []
            guard let start = parse(first["std"]), let origin = first["departureStation"] as? String else { continue }
            calls.append(ItaloScheduledCall(code: origin, arrival: start, departure: start))

            for (index, leg) in legs.enumerated() {
                guard let arrival = parse(leg["sta"]), let code = leg["arrivalStation"] as? String else { break }
                // the last leg's end is where the train stops; the others go on
                let departure = index + 1 < legs.count ? parse(legs[index + 1]["std"]) ?? arrival : arrival
                calls.append(ItaloScheduledCall(code: code, arrival: arrival, departure: departure))
            }

            if calls.count > 1 { runs.append(ItaloScheduledRun(number: number, calls: calls)) }
        }

        return runs.sorted { ($0.calls.first?.departure ?? .distantPast) < ($1.calls.first?.departure ?? .distantPast) }
    }

    private static func parse(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return timeFormatter.date(from: string)
    }

    // "2026-11-02T05:40:00", Italian wall-clock time
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Session

    /// The guest token the booking site hands every visitor, kept while it's good.
    fileprivate actor BookingSession {
        static let shared = BookingSession()

        private var current: String?
        private var fetched = Date.distantPast

        func token() async -> String? {
            if let current, Date().timeIntervalSince(fetched) < 20 * 60 { return current }

            guard let url = URL(string: "\(ItaloAPI.bookingSite)/api/login") else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "X-Anonymous-User")
            request.httpBody = Data(#"{"isAnonymous":true}"#.utf8)

            do {
                let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
                guard let http = response as? HTTPURLResponse else { return nil }
                let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                    if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
                }
                let token = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
                    .first { $0.name == "BIGSessionToken" }?.value
                if let token, !token.isEmpty {
                    current = token
                    fetched = Date()
                }
                return token
            } catch {
                print("Error getting Italo guest token: \(error)")
                return nil
            }
        }
    }

    // MARK: - Cache

    /// A search takes a few seconds, and a journey asks for the same one from
    /// several places, so an answer is kept for a while.
    fileprivate actor ScheduleCache {
        static let shared = ScheduleCache()

        private var entries: [String: (date: Date, runs: [ItaloScheduledRun])] = [:]
        private var inFlight: [String: Task<[ItaloScheduledRun], Never>] = [:]

        func runs(from origin: ItaloStation, to destination: ItaloStation, on day: Date) async -> [ItaloScheduledRun] {
            let key = "\(origin.code)>\(destination.code)@\(Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970))"

            if let entry = entries[key], Date().timeIntervalSince(entry.date) < 15 * 60 { return entry.runs }
            if let task = inFlight[key] { return await task.value }

            let task = Task { await ItaloAPI.search(from: origin, to: destination, on: day) }
            inFlight[key] = task
            let runs = await task.value
            inFlight[key] = nil
            // an empty answer is as likely a failure as a day with no trains
            if !runs.isEmpty { entries[key] = (Date(), runs) }
            return runs
        }
    }
}
