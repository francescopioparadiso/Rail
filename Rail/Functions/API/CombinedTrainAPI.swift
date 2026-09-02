import Foundation

func fetchCommonTrainList(number: String) async -> [[String: Any]] {
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
                    group.addTask { await TrenitaliaAPI().info(identifier: identifier, shouldFetchWeather: false) }
                }
            }

            if !number.isEmpty {
                group.addTask { await ItaloAPI().info(identifier: number, shouldFetchWeather: false) }
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
