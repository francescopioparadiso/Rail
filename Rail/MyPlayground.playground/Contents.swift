import Foundation

func fetch_trenitalia_info2(identifier: String, should_fetch_weather: Bool) async -> [String: Any]? {
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

let train = await fetch_trenitalia_info2(identifier: "S01700/755/1767646286400", should_fetch_weather: false)
