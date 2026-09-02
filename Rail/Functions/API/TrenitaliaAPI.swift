import Foundation

class TrenitaliaAPI {
    func suggestions(name: String) async throws -> [String] {
        let urlString = "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(name)&limit=5"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL")
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                var suggestions: [String] = []
                
                for station in jsonArray {
                    let name = station["name"] as? String ?? "Unknown"
                    
                    // do not use all-stations options
                    guard !name.contains("(") else { continue }
                    guard !name.contains("F.A.L.") else { continue }
                    
                    let formattedName = name.lowercased().capitalized
                    
                    let id = station["id"] as? Int ?? 0
                    
                    let suggestionString = "\(formattedName),\(id),trenitalia"
                    suggestions.append(suggestionString)
                }
                return suggestions
            }
            
            return []
            
        } catch {
            print("❌ Error fetching or decoding station data: \(error)")
            throw error
        }
    }
    
    func stationAutocomplete(name: String) async -> [StationSuggestion] {
        // use the lefrecce locations endpoint so the returned id can be reused as
        // departureLocationId / arrivalLocationId when fetching solutions.
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(encoded)&limit=6") else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return jsonArray.compactMap { station in
                let stationName = station["name"] as? String ?? ""
                // skip aggregate entries like "Milano ( Tutte Le Stazioni )"
                guard !stationName.contains("("), let id = station["id"] as? Int else { return nil }
                return StationSuggestion(name: stationName.lowercased().capitalized, code: String(id))
            }
        } catch {
            print("Error fetching station autocomplete: \(error)")
            return []
        }
    }

    // lightweight solutions fetch for display: parses the journey legs directly
    // from the JSON without the per-train viaggiatreno lookups (those are done
    // only when a solution is actually saved). Fetches the whole day in parallel
    // 3-hour windows (from midnight) so the list isn't capped at a single request.
    func trainSolutions(departureLocationId: String, arrivalLocationId: String, departureTime: Date) async -> [Solution] {
        guard let depId = Int(departureLocationId), let arrId = Int(arrivalLocationId) else { return [] }

        // build 3-hour windows covering the whole day (midnight → midnight)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: departureTime)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? departureTime

        var windows: [Date] = []
        var t = startOfDay
        while t < endOfDay {
            windows.append(t)
            t = calendar.date(byAdding: .hour, value: 3, to: t) ?? endOfDay
        }
        if windows.isEmpty { windows = [departureTime] }

        // fetch all windows in parallel
        let allSolutions = await withTaskGroup(of: [Solution].self) { group in
            for window in windows {
                group.addTask {
                    await self.solutionsRequest(departureLocationId: depId, arrivalLocationId: arrId, departureTime: window)
                }
            }
            var collected: [Solution] = []
            for await result in group { collected.append(contentsOf: result) }
            return collected
        }

        // de-duplicate (windows overlap) by the trains + departure times, then sort.
        // keep only solutions departing on the search day (the last window can
        // return next-day departures).
        var seen = Set<String>()
        var unique: [Solution] = []
        for solution in allSolutions.sorted(by: { $0.departureTime < $1.departureTime }) {
            guard solution.departureTime >= startOfDay, solution.departureTime < endOfDay else { continue }
            let signature = solution.segments
                .map { "\($0.number)@\($0.departureTime.timeIntervalSince1970)" }
                .joined(separator: "|")
            if seen.insert(signature).inserted { unique.append(solution) }
        }
        return unique
    }

    // single solutions request for one departure time
    private func solutionsRequest(departureLocationId: Int, arrivalLocationId: Int, departureTime: Date) async -> [Solution] {
        guard let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions") else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"

        let payload: [String: Any] = [
            "departureLocationId": departureLocationId,
            "arrivalLocationId": arrivalLocationId,
            "departureTime": formatter.string(from: departureTime),
            "adults": 1,
            "children": 0,
            "criteria": [
                "frecceOnly": false,
                "regionalOnly": false,
                "noChanges": false,
                "order": "DEPARTURE_DATE",
                "limit": 10,
                "offset": 0
            ],
            "advancedSearchRequest": ["bestFare": false]
        ]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let solutions = json["solutions"] as? [[String: Any]] else { return [] }

            var results: [Solution] = []
            for solutionDict in solutions {
                guard let solution = solutionDict["solution"] as? [String: Any],
                      let nodes = solution["nodes"] as? [[String: Any]] else { continue }

                var segments: [SolutionSegment] = []
                for node in nodes {
                    let train = node["train"] as? [String: Any]
                    guard let depString = node["departureTime"] as? String,
                          let arrString = node["arrivalTime"] as? String,
                          let dep = isoFormatter.date(from: depString),
                          let arr = isoFormatter.date(from: arrString) else { continue }

                    let acronym = train?["acronym"] as? String ?? ""
                    let isBus = acronym == "BU" || (train?["trainCategory"] as? String) == "Autobus"
                    // urban transfers come back with no train name; keep them so the
                    // journey's origin, departure and duration stay truthful
                    let number = (train?["name"] as? String) ?? ""

                    segments.append(SolutionSegment(
                        origin: node["origin"] as? String ?? "",
                        destination: node["destination"] as? String ?? "",
                        departureTime: dep,
                        arrivalTime: arr,
                        logo: acronym,
                        number: number,
                        stationCode: node["bdoOrigin"] as? String ?? "",
                        isBus: isBus,
                        isUntracked: number.isEmpty
                    ))
                }

                // lefrecce reports the fare as price.amount, with hideAmount set
                // on solutions whose price it doesn't want shown. A solution whose
                // status isn't SALEABLE can't be bought here, so it carries no fare.
                let priceInfo = solution["price"] as? [String: Any]
                let hidden = priceInfo?["hideAmount"] as? Bool ?? false
                let status = (solution["status"] as? String)?.uppercased()
                let isSaleable = status == nil || status == "SALEABLE"
                let amount = (hidden || !isSaleable) ? nil : priceInfo?["amount"] as? Double

                if !segments.isEmpty {
                    results.append(Solution(
                        segments: segments,
                        price: amount,
                        currency: priceInfo?["currency"] as? String ?? "\u{20AC}"
                    ))
                }
            }
            return results
        } catch {
            print("Error fetching solutions: \(error)")
            return []
        }
    }

    func trainList(number: String, code: String) async -> [String] {
        let urlString = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(number)"
        guard let url = URL(string: urlString) else { return [] }
        
        var results: [String] = []
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let resultString = String(data: data, encoding: .utf8) else { return [] }

            let lines = resultString.split(separator: "\n")
            
            for line in lines {
                let components = line.split(separator: "|")
                guard components.count == 2 else { continue }
                
                guard let identifierString = components.last else { continue }
                
                let identifierComponents = identifierString.split(separator: "-")
                guard let identifierNumber = identifierComponents.first else { continue }
                guard let identifierCode = identifierComponents.dropFirst().first else { continue }
                guard let identifierTimestamp = identifierComponents.last else { continue }
                
                guard identifierNumber + identifierCode == number + code else { continue }
                
                let finalIdentifier = "\(identifierCode)/\(identifierNumber)/\(identifierTimestamp)"
                
                results.append(String(finalIdentifier))
            }
        } catch {
            print("Error fetching train list for number \(number): \(error)")
            return []
        }

        return results.sorted()
    }

    func solutions(departureStation_id: String, arrivalStation_id: String) async -> [String] {
        let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions")!
        
        let allTrains = await withTaskGroup(of: [String].self) { group in
            
            for hourOffset in stride(from: 0, to: 24, by: 3) {
                group.addTask {
                    let todayStart = Calendar.current.startOfDay(for: Date())
                    guard let departureTime = Calendar.current.date(byAdding: .hour, value: hourOffset, to: todayStart) else { return [] }
                    let departureTimeFormatted = ISO8601DateFormatter().string(from: departureTime)
                    
                    let payload: [String: Any] = [
                        "departureLocationId": departureStation_id,
                        "arrivalLocationId": arrivalStation_id,
                        "departureTime": departureTimeFormatted,
                        "adults": 1,
                        "children": 0,
                        "criteria": [
                            "frecceOnly": false,
                            "regionalOnly": false,
                            "noChanges": false,
                            "order": "DEPARTURE_DATE",
                            "limit": 10,
                            "offset": 0
                        ],
                        "advancedSearchRequest": [
                            "bestFare": false
                        ]
                    ]
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    do {
                        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
                        let (data, _) = try await URLSession.shared.data(for: request)
                        
                        var nodesList: [String] = []
                        
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let solutions = json["solutions"] as? [[String: Any]] {
                            
                            let formatterISO8601 = ISO8601DateFormatter()
                            formatterISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            
                            for solutionDict in solutions {
                                if let solution = solutionDict["solution"] as? [String: Any],
                                   let nodes = solution["nodes"] as? [[String: Any]] {
                                    
                                    var trainsList: String = ""
                                    
                                    for node in nodes {
                                        let departureLocation = node["origin"] as? String ?? ""
                                        let arrivalLocation = node["destination"] as? String ?? ""
                                        let departureDate = node["departureTime"] as? String ?? ""
                                        let arrivalDate = node["arrivalTime"] as? String ?? ""
                                        let logo = (node["train"] as? [String: Any])?["acronym"] as? String ?? ""
                                        let trainNumber = (node["train"] as? [String: Any])?["name"] as? String ?? ""
                                        let stationCode = node["bdoOrigin"] as? String ?? ""
                                        
                                        guard trainNumber != "", stationCode != "" else { continue }
                                        
                                        guard let departureDateFormatted = formatterISO8601.date(from: departureDate)?.timeIntervalSince1970,
                                              let arrivalDateFormatted = formatterISO8601.date(from: arrivalDate)?.timeIntervalSince1970
                                        else { continue }
                                        
                                        let timestampFetched = await {
                                            let currentTimestamp = Int(departureDateFormatted * 1000)
                                            
                                            let identifiersFetched = await self.trainList(number: trainNumber, code: stationCode)
                                            guard identifiersFetched.count > 1 else { return currentTimestamp }
                                            
                                            let train = await self.info(identifier: identifiersFetched.first!, shouldFetchWeather: false)
                                            let stops = train?["stops"] as? [[String: Any]] ?? []
                                            
                                            guard let firstStop_depTimeId = stops.first?["dep_time_id"] as? Date else { return currentTimestamp }
                                            guard let departureStop_depTimeId = stops.filter({ ($0["name"] as? String ?? "") == departureLocation }).first?["dep_time_id"] as? Date else { return currentTimestamp }
                                            
                                            if Calendar.current.isDate(firstStop_depTimeId, inSameDayAs: departureStop_depTimeId) || Calendar.current.isDateInTomorrow(Date(timeIntervalSince1970: departureDateFormatted)) {
                                                return currentTimestamp
                                            } else {
                                                return Int(firstStop_depTimeId.timeIntervalSince1970) * 1000
                                            }
                                        }()
                                        
                                        let identifier = "\(stationCode)/\(trainNumber)/\(timestampFetched)"
                                        let payload = "\(Int(departureDateFormatted)),\(Int(arrivalDateFormatted)),\(departureLocation),\(arrivalLocation),\(logo),\(trainNumber),\(identifier)"
                                        
                                        if !payload.isEmpty {
                                            if trainsList.isEmpty {
                                                trainsList = payload
                                            } else {
                                                trainsList += ";\(payload)"
                                            }
                                        }
                                    }
                                    
                                    if !trainsList.isEmpty {
                                        let departureTimestamp = Int(trainsList.components(separatedBy: ",")[0]) ?? 0
                                        let departureDateObj = Date(timeIntervalSince1970: TimeInterval(departureTimestamp))
                                        
                                        if Calendar.current.isDateInToday(departureDateObj) {
                                            nodesList.append(trainsList)
                                        }
                                    }
                                }
                            }
                        }
                        return nodesList
                        
                    } catch {
                        print("Error in task for hour \(hourOffset): \(error)")
                        return []
                    }
                }
            }
            
            var aggregatedTrains = [String]()
            for await batch in group {
                aggregatedTrains.append(contentsOf: batch)
            }
            return aggregatedTrains
        }
        
        return Set(allTrains).sorted()
    }

    func info(identifier: String, shouldFetchWeather: Bool) async -> [String: Any]? {
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(identifier)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let compNumeroTreno = json["compNumeroTreno"] as? String ?? ""
            let parts = compNumeroTreno.split(separator: " ")
            let logo = parts.first.map(String.init) ?? ""
            let number = parts.dropFirst().first.map(String.init) ?? ""
            let lastUpdate = Date(timeIntervalSince1970: TimeInterval(json["ultimoRilev"] as? Int ?? 0) / 1000)
            var mainDelay = json["ritardo"] as? Int ?? 0
            let direction = (json["compOrientamento"] as? [String])?.first ?? ""
            let issue = json["subTitle"] as? String ?? ""

            let fermate = json["fermate"] as? [[String: Any]] ?? []
            var stops: [[String: Any]] = []

            for (i, each) in fermate.enumerated() {
                let name = (each["stazione"] as? String ?? "").capitalized
                let platform = romanToArabic(platform: each["binarioEffettivoArrivoDescrizione"] as? String
                                                    ?? (each["binarioProgrammatoArrivoDescrizione"] as? String
                                                    ?? (each["binarioEffettivoPartenzaDescrizione"] as? String
                                                    ?? (each["binarioProgrammatoPartenzaDescrizione"] as? String ?? "-"))))
                let status = each["actualFermataType"] as? Int ?? 0
                var isCompleted = false
                var isInStation = false
                var depDelay = each["ritardoPartenza"] as? Int ?? 0
                var arrDelay = each["ritaardoArrivo"] as? Int ?? 0

                let depTimeId = Date(timeIntervalSince1970: TimeInterval(each["partenza_teorica"] as? Int ?? 0)/1000)
                let arrTimeId = Date(timeIntervalSince1970: TimeInterval(each["arrivo_teorico"] as? Int ?? 0)/1000)
                var depTimeEff = each["partenzaReale"] as? Int ?? 0 == 0 ? depTimeId : Date(timeIntervalSince1970: TimeInterval(each["partenzaReale"] as? Int ?? 0)/1000)
                var arrTimeEff = each["arrivoReale"] as? Int ?? 0 == 0 ? arrTimeId : Date(timeIntervalSince1970: TimeInterval(each["arrivoReale"] as? Int ?? 0)/1000)
                let refTime = i == 0 ? depTimeId : arrTimeId

                let weather: String = await {
                    guard shouldFetchWeather else { return "" }
                    
                    guard let weatherData = try? await getWeather(lat: getLatitude(for: name), lon: getLongitude(for: name), date: refTime) else { return "" }
                    return weatherData
                }()
                print("\(logo) \(number) - Fetched weather for \(name) at \(refTime): \(weather)")

                if i == 0 {
                    if Date() < depTimeId {
                        isCompleted = false
                        isInStation = true
                    } else {
                        depDelay = Calendar.current.dateComponents([.minute], from: depTimeId, to: depTimeEff).minute!
                        isCompleted = true
                        isInStation = false
                    }
                } else if i == fermate.count - 1 {
                    arrTimeEff = Calendar.current.date(byAdding: .minute, value: mainDelay, to: arrTimeId) ?? .distantPast
                    arrDelay = Calendar.current.dateComponents([.minute], from: arrTimeId, to: arrTimeEff).minute!
                    if Date() < arrTimeEff {
                        isCompleted = false
                        isInStation = false
                    } else {
                        mainDelay = each["ritardoArrivo"] as? Int ?? 0
                        isCompleted = true
                        isInStation = true
                    }
                } else {
                    depTimeEff = Date(timeIntervalSince1970: TimeInterval(each["partenzaReale"] as? Int ?? 0)/1000) == Date(timeIntervalSince1970: 0)
                        ? Calendar.current.date(byAdding: .minute, value: mainDelay, to: depTimeId) ?? .distantPast
                        : depTimeEff
                    arrTimeEff = Date(timeIntervalSince1970: TimeInterval(each["arrivoReale"] as? Int ?? 0)/1000) == Date(timeIntervalSince1970: 0)
                        ? Calendar.current.date(byAdding: .minute, value: mainDelay, to: arrTimeId) ?? .distantPast
                        : arrTimeEff

                    arrDelay = Calendar.current.dateComponents([.minute], from: arrTimeId, to: arrTimeEff).minute!
                    depDelay = Calendar.current.dateComponents([.minute], from: depTimeId, to: depTimeEff).minute!

                    if Date() < arrTimeEff {
                        isCompleted = false
                        isInStation = false
                    } else if Date() >= arrTimeEff && Date() < depTimeEff {
                        isCompleted = false
                        isInStation = true
                    } else if Date() >= depTimeEff {
                        arrDelay = Calendar.current.dateComponents([.minute], from: arrTimeId, to: arrTimeEff).minute!
                        depDelay = Calendar.current.dateComponents([.minute], from: depTimeId, to: depTimeEff).minute!
                        isCompleted = true
                        isInStation = true
                    }
                }

                stops.append([
                    "name": name,
                    "platform": platform,
                    "weather": weather,
                    "status": status,
                    "is_completed": isCompleted,
                    "is_in_station": isInStation,
                    "dep_delay": depDelay,
                    "arr_delay": arrDelay,
                    "dep_time_id": depTimeId,
                    "arr_time_id": arrTimeId,
                    "dep_time_eff": depTimeEff,
                    "arr_time_eff": arrTimeEff,
                    "ref_time": refTime
                ])
            }

            return [
                "logo": logo,
                "number": number,
                "identifier": identifier,
                "provider": "trenitalia",
                "last_update_time": lastUpdate,
                "delay": mainDelay,
                "direction": direction,
                "issue": issue,
                "stops": stops
            ]

        } catch {
            print("Trenitalia JSON error \(identifier): \(error)")
            return nil
        }
    }
}
