import Foundation

class ItaloAPI {
    func suggestions() -> [String] {
        var stationNames: [String] = []

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
                stationNames.append(payload)
            }
        } catch {
            print("❌ Error reading CSV file: \(error)")
        }
        
        return stationNames
    }

    func solutions(depStatCode: String, depStatName: String) async throws -> [String] {
        let urlString = "https://italoinviaggio.italotreno.it/api/RicercaStazioneService?&CodiceStazione=\(depStatCode)&NomeStazione=\(depStatName)"
        
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        var solutions: [String] = []

        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            let upcomingTrains = json["ListaTreniArrivo"] as? [[String: Any]] ?? []
            
            for train in upcomingTrains {
                if let number = train["Numero"] as? String {
                     solutions.append(number)
                }
            }
        }
        
        return solutions
    }

    func info(identifier: String, shouldFetchWeather: Bool) async -> [String: Any]? {
        let urlString = "https://italoinviaggio.italotreno.it/api/RicercaTrenoService?TrainNumber=\(identifier)"
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
                    let arr_time_eff = Calendar.current.date(bySetting: .second, value: 0, of: timeToDate(timeString: each["ActualArrivalTime"] as? String ?? "")!)!
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
