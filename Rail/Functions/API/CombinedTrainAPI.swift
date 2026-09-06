import Foundation

func fetchCommonTrainList(number: String) async -> [[String: Any]] {
    var resultsArray: [[String: Any]] = []

    guard let url = URL(string: "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(number)") else { return [] }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let resultString = String(data: data, encoding: .utf8) else { return [] }

        let lines = resultString.split(separator: "\n")

        // the run dates worth looking up: today's, and yesterday's for the overnight
        // services still on the move this morning. Whether each one is actually
        // still addable is decided on its real stop times once it comes back.
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let earliestRunDay = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let earliestTimestamp = Int(earliestRunDay.timeIntervalSince1970) * 1000

        await withTaskGroup(of: [String: Any]?.self) { group in
            for line in lines {
                let parts = line.split(separator: "|")
                guard parts.count > 1 else { continue }

                let codeParts = parts[1].split(separator: "-")
                guard codeParts.count > 2 else { continue }

                let code = codeParts[1]
                let timestamp = Int(codeParts[2]) ?? 0

                if timestamp >= earliestTimestamp {
                    let identifier = "\(code)/\(number)/\(timestamp)"
                    group.addTask { await TrenitaliaAPI().info(identifier: identifier, shouldFetchWeather: false) }
                }
            }

            if !number.isEmpty {
                group.addTask { await ItaloAPI().info(identifier: number, shouldFetchWeather: false) }
            }

            for await result in group {
                if let result = result, isTrainAddable(info: result) { resultsArray.append(result) }
            }
        }

    } catch {
        print("Error fetching train list: \(error)")
    }

    return resultsArray
}
