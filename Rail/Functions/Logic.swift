import Foundation

// MARK: - Common functions
func fetch_common_train_list(number: String) async -> [[String: Any]] {
    var resultsArray: [[String: Any]] = []

    guard let url = URL(string: "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(number)") else { return [] }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let resultString = String(data: data, encoding: .utf8) else { return [] }

        let lines = resultString.split(separator: "\n")

        await withTaskGroup(of: [String: Any]?.self) { group in
            for line in lines {
                let parts = line.split(separator: "|")
                guard parts.count > 1 else { continue }

                let codeParts = parts[1].split(separator: "-")
                guard codeParts.count > 2 else { continue }

                let code = codeParts[1]
                let timestamp = Int(codeParts[2]) ?? 0
                let todayTimestamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) * 1000

                if timestamp >= todayTimestamp {
                    let identifier = "\(code)/\(number)/\(timestamp)"
                    group.addTask { await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: true) }
                }
            }

            if !number.isEmpty {
                group.addTask { await ItaloAPI().info(identifier: number) }
            }

            for await result in group {
                if let result = result { resultsArray.append(result) }
            }
        }

    } catch {
        print("Error fetching train list: \(error)")
    }

    return resultsArray
}


// MARK: - Trenitalia functions
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
    
    func train_list(number: String, code: String) async -> [String] {
        let url_string = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(number)"
        guard let url = URL(string: url_string) else { return [] }
        
        var results: [String] = []
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let resultString = String(data: data, encoding: .utf8) else { return [] }

            let lines = resultString.split(separator: "\n")
            
            for line in lines {
                let components = line.split(separator: "|")
                guard components.count == 2 else { continue }
                
                guard let identifier_string = components.last else { continue }
                
                let identifier_components = identifier_string.split(separator: "-")
                guard let identifier_number = identifier_components.first else { continue }
                guard let identifier_code = identifier_components.dropFirst().first else { continue }
                guard let identifier_timestamp = identifier_components.last else { continue }
                
                guard identifier_number + identifier_code == number + code else { continue }
                
                let final_identifier = "\(identifier_code)/\(identifier_number)/\(identifier_timestamp)"
                
                results.append(String(final_identifier))
            }
        } catch {
            print("Error fetching train list for number \(number): \(error)")
            return []
        }

        return results.sorted()
    }

    func solutions(departureStation_id: String, arrivalStation_id: String) async -> [String] {
        let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions")!
        
        // Use TaskGroup to execute requests in parallel
        let allTrains = await withTaskGroup(of: [String].self) { group in
            
            for hourOffset in stride(from: 0, to: 24, by: 3) {
                group.addTask {
                    // parameters for url
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
                    
                    // request setup
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    do {
                        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
                        let (data, _) = try await URLSession.shared.data(for: request)
                        
                        var nodes_list: [String] = []
                        
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let solutions = json["solutions"] as? [[String: Any]] {
                            
                            let formatterISO8601 = ISO8601DateFormatter()
                            formatterISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            
                            for solutionDict in solutions {
                                if let solution = solutionDict["solution"] as? [String: Any],
                                   let nodes = solution["nodes"] as? [[String: Any]] {
                                    
                                    var trains_list: String = ""
                                    
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
                                        
                                        let timestamp_fetched = await {
                                            let current_timestamp = Int(departureDateFormatted * 1000)
                                            
                                            let identifiers_fetched = await self.train_list(number: trainNumber, code: stationCode)
                                            guard identifiers_fetched.count > 1 else { return current_timestamp }
                                            
                                            let train = await self.info(identifier: identifiers_fetched.first!, should_fetch_weather: false)
                                            let stops = train?["stops"] as? [[String: Any]] ?? []
                                            
                                            guard let firstStop_depTimeId = stops.first?["dep_time_id"] as? Date else { return current_timestamp }
                                            guard let departureStop_depTimeId = stops.filter({ ($0["name"] as? String ?? "") == departureLocation }).first?["dep_time_id"] as? Date else { return current_timestamp }
                                            
                                            if Calendar.current.isDate(firstStop_depTimeId, inSameDayAs: departureStop_depTimeId) || Calendar.current.isDateInTomorrow(Date(timeIntervalSince1970: departureDateFormatted)) {
                                                return current_timestamp
                                            } else {
                                                return Int(firstStop_depTimeId.timeIntervalSince1970) * 1000
                                            }
                                        }()
                                        
                                        let identifier = "\(stationCode)/\(trainNumber)/\(timestamp_fetched)"
                                        let payload = "\(Int(departureDateFormatted)),\(Int(arrivalDateFormatted)),\(departureLocation),\(arrivalLocation),\(logo),\(trainNumber),\(identifier)"
                                        
                                        if !payload.isEmpty {
                                            if trains_list.isEmpty {
                                                trains_list = payload
                                            } else {
                                                trains_list += ";\(payload)"
                                            }
                                        }
                                    }
                                    
                                    if !trains_list.isEmpty {
                                        let departureTimestamp = Int(trains_list.components(separatedBy: ",")[0]) ?? 0
                                        let departureDateObj = Date(timeIntervalSince1970: TimeInterval(departureTimestamp))
                                        
                                        if Calendar.current.isDateInToday(departureDateObj) {
                                            nodes_list.append(trains_list)
                                        }
                                    }
                                }
                            }
                        }
                        return nodes_list
                        
                    } catch {
                        print("Error in task for hour \(hourOffset): \(error)")
                        return []
                    }
                }
            }
            
            // Collect all results
            var aggregatedTrains = [String]()
            for await batch in group {
                aggregatedTrains.append(contentsOf: batch)
            }
            return aggregatedTrains
        }
        
        // Deduplicate and Sort
        return Set(allTrains).sorted()
    }

    func info(identifier: String, should_fetch_weather: Bool) async -> [String: Any]? {
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
                    guard should_fetch_weather else { return "" }
                    
                    guard let weatherData = try? await get_weather(lat: get_latitude(for: name), lon: get_longitude(for: name), date: refTime) else { return "" }
                    return weatherData
                }()
                print("\(logo) \(number) - Fetched weather for \(name) at \(refTime): \(weather)")

                // Logic for first, last, middle stations
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


// MARK: - Italo functions
class ItaloAPI {
    func suggestions() -> [String] {
        var station_names: [String] = []

        guard let filePath = Bundle.main.path(forResource: "italo_stations", ofType: "csv") else {
            print("❌ Error: italo_stations.csv not found in bundle")
            return []
        }

        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            let rows = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            for row in rows.dropFirst() {
                let columns = row.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                let name = columns[0]
                let code = columns[1]
                
                let payload = "\(name),\(code),italo"
                station_names.append(payload)
            }
        } catch {
            print("❌ Error reading CSV file: \(error)")
        }
        
        return station_names
    }

    func solutions(dep_stat_code: String, dep_stat_name: String) async throws -> [String] {
        let urlString = "https://italoinviaggio.italotreno.it/api/RicercaStazioneService?&CodiceStazione=\(dep_stat_code)&NomeStazione=\(dep_stat_name)"
        
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        var solutions: [String] = []

        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            let upcoming_trains = json["ListaTreniArrivo"] as? [[String: Any]] ?? []
            
            for train in upcoming_trains {
                if let number = train["Numero"] as? String {
                     solutions.append(number)
                }
            }
        }
        
        return solutions
    }

    func info(identifier: String) async -> [String: Any]? {
        let urlString = "https://italoinviaggio.italotreno.it/api/RicercaTrenoService?TrainNumber=\(identifier)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            if let trainSchedule = json["TrainSchedule"] as? [String:Any] {
                let train_number = trainSchedule["TrainNumber"] as? String ?? ""
                
                let last_update_time = time_to_date(timeString: json["LastUpdate"] as? String ?? "") ?? .distantPast
                
                let main_delay = (trainSchedule["Distruption"] as? [String: Any])?["DelayAmount"] as? Int ?? 0
                
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
                    
                    let dep_time_id = Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["EstimatedDepartureTime"] as? String ?? "")!)!
                    let arr_time_id = Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["EstimatedArrivalTime"] as? String ?? "")!)!
                    var dep_time_eff = Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")!)!
                    let arr_time_eff = Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["ActualArrivalTime"] as? String ?? "")!)!
                    let ref_time = i == 0 ? dep_time_id : arr_time_id
                    
                    let weather = try await getOpenMeteoWeather(lat: get_latitude(for: name), lon: get_longitude(for: name), date: ref_time)
                    
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
                        arr_delay = main_delay
                        
                        if Date() < arr_time_eff {
                            is_completed = false
                            is_in_station = false
                        } else {
                            is_completed = true
                            is_in_station = true
                        }
                    } else {
                        // middle stations
                        dep_time_eff = Calendar.current.date(byAdding: .minute, value: main_delay, to: dep_time_id)!
                        
                        if Date() < arr_time_eff {
                            is_completed = false
                            is_in_station = false
                        } else if Date() >= arr_time_eff && Date() < dep_time_eff {
                            is_completed = false
                            is_in_station = true
                        } else if Date() >= dep_time_eff {
                            if time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")! != .distantPast {
                                dep_time_eff = time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")!
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
                    "number": train_number,
                    "identifier": identifier,
                    "provider": "italo",
                    
                    "last_update_time": last_update_time,
                    "delay": main_delay,
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
