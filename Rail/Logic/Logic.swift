import Foundation
import UIKit

func fetch_train_list(number: String, completion: @escaping ([[String: Any]]) -> Void) {
    var resultsArray: [[String: Any]] = []

    let urlString = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(String(number))"

    guard let url = URL(string: urlString) else {
        return
    }
    
    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print("Error fetching train data: \(error)")
            return
        }
        
        guard let data = data, let resultString = String(data: data, encoding: .utf8) else {
            return
        }
        
        DispatchQueue.main.async {
            let results = resultString.split(separator: "\n")
            
            let dispatchGroup = DispatchGroup()
            
            for each in results {
                guard each.split(separator: "|").dropFirst().first != nil else {
                    print("Access denied error: Missing '|' separator or element after it.")
                    break
                }
                
                let code = each.split(separator: "|")[1].split(separator: "-")[1]
                let timestamp = Int(each.split(separator: "|")[1].split(separator: "-")[2]) ?? 0
                
                let today_timestamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) * 1000
                
                if timestamp >= today_timestamp {
                    let identifier = "\(code)/\(number)/\(timestamp)"
                    
                    dispatchGroup.enter()
                    fetch_trenitalia_train_info(identifier: identifier) { result in
                        resultsArray.append(result)
                        dispatchGroup.leave()
                    }
                }
            }
            if !number.isEmpty {
                dispatchGroup.enter()
                fetch_italo_train_info(identifier: number) { result in
                    resultsArray.append(result)
                    dispatchGroup.leave()
                }
            }
            
            // Wait for all fetches to complete
            dispatchGroup.notify(queue: .main) {
                completion(resultsArray)
            }
        }
    }.resume()
}

func fetch_trenitalia_train_info(identifier: String, completion: @escaping ([String: Any]) -> Void) {
    
    let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(identifier)"
    print(urlString)
    
    guard let url = URL(string: urlString) else { return }
    
    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data else { return }
        
        Task {
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    let compNumeroTreno = json["compNumeroTreno"] as? String ?? ""
                    let number = String(compNumeroTreno.split(separator: " ")[1])
                    let logo = String(compNumeroTreno.split(separator: " ")[0])
                    
                    let last_update_time = Date(timeIntervalSince1970: TimeInterval(json["ultimoRilev"] as? Int ?? 0) / 1000)
                    var main_delay = json["ritardo"] as? Int ?? 0
                    let direction = ((json["compOrientamento"] as? [String])?.first == "--" ? "" : (json["compOrientamento"] as? [String])?.first) ?? ""
                    
                    let issue = json["subTitle"] as? String ?? ""
                    
                    var stops: [[String: Any]] = []
                    let fermate = json["fermate"] as? [[String: Any]] ?? []
                    for (i,each) in fermate.enumerated() {
                        let name = String(each["stazione"] as? String ?? "").capitalized
                        let platform = await romanToArabic(platform: String(each["binarioEffettivoArrivoDescrizione"] as? String ?? (each["binarioProgrammatoArrivoDescrizione"] as? String ?? (each["binarioEffettivoPartenzaDescrizione"] as? String ?? (each["binarioProgrammatoPartenzaDescrizione"] as? String ?? "-")))))
                        
                        let status = each["actualFermataType"] as? Int ?? 0
                        var is_completed = false
                        var is_in_station = false
                        var dep_delay = each["ritardoPartenza"] as? Int ?? 0
                        var arr_delay = each["ritaardoArrivo"] as? Int ?? 0
                        
                        let dep_time_id = Calendar.current.date(bySetting: .second, value: 0, of: Date(timeIntervalSince1970: TimeInterval(each["partenza_teorica"] as? Int ?? 0) / 1000))!
                        let arr_time_id = Calendar.current.date(bySetting: .second, value: 0, of: Date(timeIntervalSince1970: TimeInterval(each["arrivo_teorico"] as? Int ?? 0) / 1000))!
                        var dep_time_eff = Date(timeIntervalSince1970: TimeInterval(each["partenzaReale"] as? Int ?? 0) / 1000) == Date(timeIntervalSince1970: 0) ? dep_time_id : Calendar.current.date(bySetting: .second, value: 0, of: Date(timeIntervalSince1970: TimeInterval(each["partenzaReale"] as? Int ?? 0) / 1000))!
                        var arr_time_eff = Date(timeIntervalSince1970: TimeInterval(each["arrivoReale"] as? Int ?? 0) / 1000) == Date(timeIntervalSince1970: 0) ? arr_time_id : Calendar.current.date(bySetting: .second, value: 0, of: Date(timeIntervalSince1970: TimeInterval(each["arrivoReale"] as? Int ?? 0) / 1000))!
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
                            arr_time_eff = Calendar.current.date(byAdding: .minute, value: main_delay, to: arr_time_id) ?? .distantPast
                            
                            arr_delay = Calendar.current.dateComponents([.minute], from: arr_time_id, to: arr_time_eff).minute!
                            
                            if Date() < arr_time_eff {
                                is_completed = false
                                is_in_station = false
                            } else {
                                arr_delay = Calendar.current.dateComponents([.minute], from: arr_time_id, to: arr_time_eff).minute!
                                main_delay = each["ritardoArrivo"] as? Int ?? 0
                                is_completed = true
                                is_in_station = true
                            }
                        } else {
                            // middle stations
                            arr_time_eff = Date(timeIntervalSince1970: TimeInterval(each["arrivoReale"] as? Int ?? 0) / 1000) == Date(timeIntervalSince1970: 0) ? Calendar.current.date(byAdding: .minute, value: main_delay, to: arr_time_id) ?? .distantPast : arr_time_eff
                            dep_time_eff = Date(timeIntervalSince1970: TimeInterval(each["partenzaReale"] as? Int ?? 0) / 1000) == Date(timeIntervalSince1970: 0) ? Calendar.current.date(byAdding: .minute, value: main_delay, to: dep_time_id) ?? .distantPast : dep_time_eff
                            
                            arr_delay = Calendar.current.dateComponents([.minute], from: arr_time_id, to: arr_time_eff).minute!
                            dep_delay = Calendar.current.dateComponents([.minute], from: dep_time_id, to: dep_time_eff).minute!
                            
                            if Date() < arr_time_eff {
                                is_completed = false
                                is_in_station = false
                            } else if Date() >= arr_time_eff && Date() < dep_time_eff {
                                is_completed = false
                                is_in_station = true
                            } else if Date() >= dep_time_eff {
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
                    
                    let result = [
                        "logo": logo,
                        "number": number,
                        "identifier": identifier,
                        "provider": "trenitalia",
                        
                        "last_update_time": last_update_time,
                        "delay": main_delay,
                        "direction": direction,
                        
                        "issue": issue,
                        
                        "stops": stops
                    ]
                    
                    completion(result)
                }
            } catch {
                print("JSON decoding error: \(error)")
            }
        }
    }.resume()
}

func fetch_italo_train_info(identifier: String, completion: @escaping ([String: Any]) -> Void) {
    
    let urlString = "https://italoinviaggio.italotreno.it/api/RicercaTrenoService?number=\(identifier)"
    
    guard let url = URL(string: urlString) else { return }
    
    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data else { return }
        
        Task {
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let isEmpty = json["IsEmpty"] as? Int, isEmpty == 1 {
                        return
                    } else {
                        if let trainSchedule = json["TrainSchedule"] as? [String:Any] {
                            let train_number = trainSchedule["TrainNumber"] as? String ?? ""
                            
                            let last_update_time = await time_to_date(timeString: json["LastUpdate"] as? String ?? "") ?? .distantPast
                            
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
                                let platform = await romanToArabic(platform: each["ActualArrivalPlatform"] as? String ?? "-")
                                
                                let status = 0
                                var is_completed = false
                                var is_in_station = false
                                var dep_delay = 0
                                var arr_delay = 0
                                
                                let dep_time_id = await Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["EstimatedDepartureTime"] as? String ?? "")!)!
                                let arr_time_id = await Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["EstimatedArrivalTime"] as? String ?? "")!)!
                                var dep_time_eff = await Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")!)!
                                let arr_time_eff = await Calendar.current.date(bySetting: .second, value: 0, of: time_to_date(timeString: each["ActualArrivalTime"] as? String ?? "")!)!
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
                                        if await time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")! != .distantPast {
                                            dep_time_eff = await time_to_date(timeString: each["ActualDepartureTime"] as? String ?? "")!
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
                            
                            let result = [
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
                            
                            completion(result)
                        }
                    }
                }
            } catch {
                print("JSON decoding error: \(error)")
            }
        }
    }.resume()
}
