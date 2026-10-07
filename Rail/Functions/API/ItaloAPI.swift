import Foundation

/// A station Italo calls at: one row of `italo_stations.csv`, tying Italo's own
/// names and codes to the ids the rest of the app searches and reads boards with.
struct ItaloStation: Hashable {
    /// The name Italo's board is asked for, "Milano Centrale".
    let name: String
    /// Italo's code, "MC_".
    let code: String
    /// How Italo's routes print it, "Mediopadana R.Emilia".
    let routeName: String
    /// The lefrecce location id the journey search picks, "830001700".
    let trenitaliaID: String
    /// The viaggiatreno code the timetable reads, "S01700".
    let viaggiatrenoCode: String
}

/// A stop an Italo train makes, as the board prints its route.
struct ItaloCall: Hashable {
    let name: String
    let time: Date
}

/// One train on an Italo station board.
struct ItaloBoardEntry: Hashable {
    let number: String
    /// Where it's bound for on departures, where it comes from on arrivals.
    let counterpart: String
    let scheduledTime: Date
    let delayMinutes: Int
    let platform: String
    /// The stops after this station on departures, before it on arrivals. Empty
    /// when the board leaves the route out, which it does for some trains.
    let route: [ItaloCall]
}

class ItaloAPI {
    private static let baseURL = "https://italoinviaggio.italotreno.com/api"

    // MARK: - Stations

    static let stations: [ItaloStation] = {
        guard let filePath = Bundle.main.path(forResource: "italo_stations", ofType: "csv"),
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("❌ Error: italo_stations.csv not found in bundle")
            return []
        }

        return content.components(separatedBy: "\n").dropFirst().compactMap { row in
            let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count == 5 else { return nil }
            return ItaloStation(
                name: columns[0],
                code: columns[1],
                routeName: columns[2],
                trenitaliaID: columns[3],
                viaggiatrenoCode: columns[4]
            )
        }
    }()

    static func station(trenitaliaID: String) -> ItaloStation? {
        stations.first { $0.trenitaliaID == trenitaliaID }
    }

    static func station(viaggiatrenoCode: String) -> ItaloStation? {
        stations.first { $0.viaggiatrenoCode == viaggiatrenoCode }
    }

    // MARK: - Board

    /// Italo's live board for `station`: what is due over roughly the next two
    /// hours, and nothing further ahead — the board is all Italo publishes.
    /// Italobus connections are left out, having no route that can be followed.
    static func board(_ kind: StationBoardKind, at station: ItaloStation) async -> [ItaloBoardEntry] {
        var components = URLComponents(string: "\(baseURL)/RicercaStazioneService")
        components?.queryItems = [
            URLQueryItem(name: "CodiceStazione", value: station.code),
            URLQueryItem(name: "NomeStazione", value: station.name)
        ]
        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            let key = kind == .departures ? "ListaTreniPartenza" : "ListaTreniArrivo"
            let entries = json[key] as? [[String: Any]] ?? []
            return entries.compactMap { boardEntry(from: $0, kind: kind) }
        } catch {
            print("Error fetching Italo board \(station.code): \(error)")
            return []
        }
    }

    private static func boardEntry(from entry: [String: Any], kind: StationBoardKind) -> ItaloBoardEntry? {
        // trains run on four-digit numbers, Italobus on five
        guard let number = entry["Numero"] as? String, number.count == 4,
              let scheduled = clockTime(entry["OraPassaggio"] as? String ?? "", near: Date()) else { return nil }

        // "Milano Expo Rho (10.41) - Torino Porta di Susa (11.24)"
        let route: [ItaloCall] = (entry["InfoRoute"] as? String ?? "")
            .components(separatedBy: " - ")
            .compactMap { part in
                guard let open = part.lastIndex(of: "(") else { return nil }
                let name = part[..<open].trimmingCharacters(in: .whitespaces)
                let clock = part[part.index(after: open)...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
                    .replacingOccurrences(of: ".", with: ":")
                // a stop's clock is read on the same side of this one as the route runs
                guard !name.isEmpty, var time = clockTime(clock, near: scheduled) else { return nil }
                if kind == .departures, time < scheduled {
                    time = Calendar.current.date(byAdding: .day, value: 1, to: time) ?? time
                } else if kind == .arrivals, time > scheduled {
                    time = Calendar.current.date(byAdding: .day, value: -1, to: time) ?? time
                }
                return ItaloCall(name: name, time: time)
            }

        return ItaloBoardEntry(
            number: number,
            counterpart: (entry["DescrizioneLocalita"] as? String ?? "").capitalized,
            scheduledTime: scheduled,
            delayMinutes: entry["Ritardo"] as? Int ?? 0,
            platform: entry["Binario"] as? String ?? "",
            route: route
        )
    }

    // MARK: - Solutions

    /// The direct Italo trains from one station to the other. Italo's booking
    /// site timetables them on any day; when it can't be reached, today's live
    /// board still gives the trains leaving in the next couple of hours.
    func trainSolutions(
        origin: String,
        departureLocationId: String,
        destination: String,
        arrivalLocationId: String,
        departureTime: Date
    ) async -> [Solution] {
        guard let from = Self.station(trenitaliaID: departureLocationId),
              let to = Self.station(trenitaliaID: arrivalLocationId),
              from != to else { return [] }

        let runs = await Self.scheduledRuns(from: from, to: to, on: departureTime)
        if !runs.isEmpty {
            let cutoff = Calendar.current.dateInterval(of: .minute, for: departureTime)?.start ?? departureTime
            return runs.compactMap { run in
                guard let first = run.calls.first, let last = run.calls.last, first.departure >= cutoff else { return nil }
                return Solution(segments: [
                    SolutionSegment(
                        origin: origin,
                        destination: destination,
                        departureTime: first.departure,
                        arrivalTime: last.arrival,
                        logo: "ITALO",
                        number: run.number,
                        stationCode: from.code,
                        isBus: false
                    )
                ])
            }
        }

        guard Calendar.current.isDateInToday(departureTime) else { return [] }

        let departures = await Self.board(.departures, at: from)

        let arrivals = await withTaskGroup(of: (ItaloBoardEntry, Date?).self) { group in
            for entry in departures {
                group.addTask { (entry, await Self.arrival(of: entry, from: from, at: to)) }
            }

            var arrivals: [(ItaloBoardEntry, Date)] = []
            for await (entry, arrival) in group {
                if let arrival { arrivals.append((entry, arrival)) }
            }
            return arrivals
        }

        let solutions = arrivals.map { entry, arrival in
            Solution(segments: [
                SolutionSegment(
                    origin: origin,
                    destination: destination,
                    departureTime: entry.scheduledTime,
                    arrivalTime: arrival,
                    logo: "ITALO",
                    number: entry.number,
                    stationCode: from.code,
                    isBus: false
                )
            ])
        }
        return solutions.sorted { $0.departureTime < $1.departureTime }
    }

    /// When the train reaches `station` after leaving `origin`, or nil when it
    /// doesn't call there. The board's route answers it; for the trains the board
    /// prints no route for, the train's own schedule does.
    private static func arrival(of entry: ItaloBoardEntry, from origin: ItaloStation, at station: ItaloStation) async -> Date? {
        if !entry.route.isEmpty {
            return entry.route.first { matches($0.name, station) }?.time
        }

        let calls = await schedule(number: entry.number)
        let start = calls.firstIndex { matches($0.name, origin) }.map { $0 + 1 } ?? 0
        return calls[start...].first { matches($0.name, station) && $0.time > entry.scheduledTime }?.time
    }

    /// Every stop on today's run of `number`, at the time it's timetabled there.
    private static func schedule(number: String) async -> [ItaloCall] {
        guard let url = URL(string: "\(baseURL)/RicercaTrenoService?TrainNumber=\(number)") else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let schedule = json["TrainSchedule"] as? [String: Any] else { return [] }

            var stops: [[String: Any]] = [schedule["StazionePartenza"] as? [String: Any] ?? [:]]
            stops.append(contentsOf: schedule["StazioniFerme"] as? [[String: Any]] ?? [])
            stops.append(contentsOf: schedule["StazioniNonFerme"] as? [[String: Any]] ?? [])

            var previous: Date?
            return stops.compactMap { stop in
                // "01:00" is Italo's blank: the origin has no arrival time
                let arrival = stop["EstimatedArrivalTime"] as? String ?? ""
                let clock = arrival == "01:00" ? stop["EstimatedDepartureTime"] as? String ?? "" : arrival
                guard let name = stop["LocationDescription"] as? String,
                      var time = clockTime(clock, near: previous ?? Date()) else { return nil }
                if let previous, time < previous {
                    time = Calendar.current.date(byAdding: .day, value: 1, to: time) ?? time
                }
                previous = time
                return ItaloCall(name: name, time: time)
            }
        } catch {
            print("Error fetching Italo schedule \(number): \(error)")
            return []
        }
    }

    // MARK: - Helpers

    /// Whether a name from an Italo route is `station`, going by either of the
    /// names Italo gives it.
    static func matches(_ name: String, _ station: ItaloStation) -> Bool {
        let target = comparable(name)
        return target == comparable(station.routeName) || target == comparable(station.name)
    }

    /// Letters and digits only, accents folded, so "S.Donà-Jesolo" and
    /// "S. Dona Jesolo" read alike.
    static func comparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// "11:24" on the day that puts it closest to `reference`: a board read just
    /// before midnight lists the trains just after it as well.
    private static func clockTime(_ clock: String, near reference: Date) -> Date? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }

        let calendar = Calendar.current
        guard let time = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: reference) else { return nil }
        let halfDay: TimeInterval = 12 * 3600
        if time.timeIntervalSince(reference) > halfDay {
            return calendar.date(byAdding: .day, value: -1, to: time)
        }
        if reference.timeIntervalSince(time) > halfDay {
            return calendar.date(byAdding: .day, value: 1, to: time)
        }
        return time
    }

    // MARK: - Train

    func info(identifier: String, shouldFetchWeather: Bool) async -> [String: Any]? {
        let urlString = "\(Self.baseURL)/RicercaTrenoService?TrainNumber=\(identifier)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            if let trainSchedule = json["TrainSchedule"] as? [String:Any] {
                let trainNumber = trainSchedule["TrainNumber"] as? String ?? ""
                
                let last_update_time = timeToDate(timeString: json["LastUpdate"] as? String ?? "") ?? .distantPast
                
                let mainDelay = (trainSchedule["Distruption"] as? [String: Any])?["DelayAmount"] as? Int ?? 0
                
                let direction = (trainSchedule["Leg"] as? [String: Any])?["TrainOrientation"] as? String ?? ""
                
                let issue = (trainSchedule["Distruption"] as? [String: Any])?["Warning"] as? String ?? ""
                
                var stops: [[String: Any]] = []
                var fermate: [[String: Any]] = []
                fermate.append(trainSchedule["StazionePartenza"] as? [String: Any] ?? [:])
                fermate.append(contentsOf: trainSchedule["StazioniFerme"] as? [[String: Any]] ?? [])
                fermate.append(contentsOf: trainSchedule["StazioniNonFerme"] as? [[String: Any]] ?? [])
                
                for (i,each) in fermate.enumerated() {
                    let name = (each["LocationDescription"] as? String ?? "").capitalized
                    let platform = romanToArabic(platform: each["ActualArrivalPlatform"] as? String ?? "-")
                    
                    let status = 0
                    var is_completed = false
                    var is_in_station = false
                    var dep_delay = 0
                    var arr_delay = 0
                    
                    let dep_time_id = Calendar.current.date(bySetting: .second, value: 0, of: timeToDate(timeString: each["EstimatedDepartureTime"] as? String ?? "")!)!
                    let arr_time_id = Calendar.current.date(bySetting: .second, value: 0, of: timeToDate(timeString: each["EstimatedArrivalTime"] as? String ?? "")!)!
                    var dep_time_eff = Calendar.current.date(bySetting: .second, value: 0, of: timeToDate(timeString: each["ActualDepartureTime"] as? String ?? "")!)!
                    var arr_time_eff = Calendar.current.date(bySetting: .second, value: 0, of: timeToDate(timeString: each["ActualArrivalTime"] as? String ?? "")!)!
                    let ref_time = i == 0 ? dep_time_id : arr_time_id
                    
                    let weather: String = await {
                        guard shouldFetchWeather else { return "" }
                        do {
                            return try await getWeather(lat: getLatitude(for: name), lon: getLongitude(for: name), date: ref_time)
                        } catch {
                            return ""
                        }
                    }()
                    
                    if i == 0 {
                        // first station
                        if Date() < dep_time_id {
                            is_completed = false
                            is_in_station = true
                        } else {
                            dep_delay = Calendar.current.dateComponents([.minute], from: dep_time_id, to: dep_time_eff).minute!
                            is_completed = true
                            is_in_station = false
                        }
                    } else if i == fermate.count - 1 {
                        // last station
                        arr_delay = mainDelay
                        
                        if Date() < arr_time_eff {
                            is_completed = false
                            is_in_station = false
                        } else {
                            is_completed = true
                            is_in_station = true
                        }
                    } else {
                        // middle stations
                        dep_time_eff = Calendar.current.date(byAdding: .minute, value: mainDelay, to: dep_time_id)!
                        if timeToDate(timeString: each["ActualArrivalTime"] as? String ?? "")! == .distantPast {
                            arr_time_eff = Calendar.current.date(byAdding: .minute, value: mainDelay, to: arr_time_id)!
                        }
                        
                        // stops still ahead carry the expected delay too, so a segment
                        // that starts or ends here shows the train as late
                        arr_delay = Calendar.current.dateComponents([.minute], from: arr_time_id, to: arr_time_eff).minute!
                        dep_delay = mainDelay
                        
                        if Date() < arr_time_eff {
                            is_completed = false
                            is_in_station = false
                        } else if Date() >= arr_time_eff && Date() < dep_time_eff {
                            is_completed = false
                            is_in_station = true
                        } else if Date() >= dep_time_eff {
                            if timeToDate(timeString: each["ActualDepartureTime"] as? String ?? "")! != .distantPast {
                                dep_time_eff = timeToDate(timeString: each["ActualDepartureTime"] as? String ?? "")!
                            }
                            arr_delay = Calendar.current.dateComponents([.minute], from: arr_time_id, to: arr_time_eff).minute!
                            dep_delay = Calendar.current.dateComponents([.minute], from: dep_time_id, to: dep_time_eff).minute!
                            is_completed = true
                            is_in_station = true
                        }
                    }
                    
                    stops.append([
                        "name": name,
                        "platform": platform,
                        "weather": weather,
                        
                        "status": status,
                        "is_completed": is_completed,
                        "is_in_station": is_in_station,
                        
                        "dep_delay": dep_delay,
                        "arr_delay": arr_delay,
                        
                        "dep_time_id": dep_time_id,
                        "arr_time_id": arr_time_id,
                        "dep_time_eff": dep_time_eff,
                        "arr_time_eff": arr_time_eff,
                        "ref_time": ref_time
                    ])
                }
                
                return [
                    "logo": "ITALO",
                    "number": trainNumber,
                    "identifier": identifier,
                    "provider": "italo",
                    
                    "last_update_time": last_update_time,
                    "delay": mainDelay,
                    "direction": direction,
                    
                    "issue": issue,
                    
                    "stops": stops
                ]
            }
            return nil
            
        } catch {
            print("Italo JSON error \(identifier): \(error)")
            return nil
        }
    }
}
