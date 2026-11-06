import SwiftUI
import SwiftData
import UIKit

extension PreviewMockData {
    /// The moment the mock journeys are staged around: 9904 is long in, 3223 is
    /// pulling into Savigliano, and 3224 has not left yet.
    @MainActor
    static let moment: Date = Calendar.current.date(
        bySettingHour: 9, minute: 30, second: 0, of: Date()
    ) ?? Date()

    /// 3224, fixed so a screenshot run can open its details by id.
    static let detailsTrainID = UUID(uuidString: "32240000-0000-0000-0000-000000003224")!

    /// A full app's worth of data, in memory: the profile and its mailboxes, today's
    /// three journeys, past ones, seats, favourites and passes. Shared by the main
    /// preview and the screenshot run (`ScreenshotMode`).
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
    
        container.mainContext.insert(
            UserProfile(
                name: "Francesco",
                photo: PreviewMockData.profilePhoto(),
                emails: [
                    PreviewMockData.appleAccount(),
                    PreviewMockData.googleAccount()
                ]
            )
        )
    
        func time(_ hour: Int, _ min: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: min, second: 0, of: Date()) ?? .distantPast
        }
    
        let mockImageData = UIImage(named: "sample_code")?.pngData()
    
        let train1 = Train(id: UUID(), logo: "ITALO", number: "9904", identifier: "IT9904", provider: "italo", last_update_time: Date(), delay: -2, direction: "Milano Centrale", issue: "")
        let train2 = Train(id: detailsTrainID, logo: "REG", number: "3224", identifier: "REG3224", provider: "trenitalia", last_update_time: Date(), delay: 5, direction: "Carmagnola", issue: "Corsa terminata a Carmagnola per un guasto sulla linea.")
        let train3 = Train(id: UUID(), logo: "REG", number: "3223", identifier: "REG3223", provider: "trenitalia", last_update_time: Date(), delay: 3, direction: "Savigliano", issue: "")
    
        [train1, train2, train3].forEach { context.insert($0) }
    
        let stopData2: [(String, Int, Int, String, Int, Int, Int, String)] = [
            ("Cuneo", 9, 24, "☀️ 10°C", 0, 0, 0, "3"),
            ("Centallo", 9, 34, "☀️ 10°C", 0, -2, -1, "1"),
            ("Fossano", 9, 43, "🌤️ 11°C", 0, 0, 0, "4"),
            ("Savigliano", 9, 51, "🌤️ 11°C", 2, 0, 0, "2"),
            ("Cavallermaggiore", 9, 57, "🌥️ 12°C", 0, 3, 4, "1"),
            ("Carmagnola", 10, 9, "🌥️ 12°C", 0, 5, 0, "3"),
            ("Torino Lingotto", 10, 28, "☁️ 9°C", 3, 0, 0, "--"),
            ("Torino Porta Nuova", 10, 35, "☁️ 9°C", 3, 0, 0, "--")
        ]
    
        let selectedStations = ["Savigliano", "Cavallermaggiore", "Carmagnola", "Torino Lingotto", "Torino Porta Nuova"]
    
        for (name, h, m, weatherStr, statusValue, aDelay, dDelay, plat) in stopData2 {
            let isLastValid = name == "Carmagnola"
            let isFirst = name == "Cuneo"
            let scheduledArr = time(h, m)
            let scheduledDep = time(h, m + 1)
        
            context.insert(Stop(
                id: train2.id, name: name, platform: plat, weather: weatherStr,
                is_selected: selectedStations.contains(name), status: statusValue,
                is_completed: name != "Torino Lingotto" && name != "Torino Porta Nuova",
                is_in_station: isLastValid, dep_delay: dDelay, arr_delay: aDelay,
                dep_time_id: isLastValid ? .distantPast : scheduledDep,
                arr_time_id: isFirst ? .distantPast : scheduledArr,
                dep_time_eff: isLastValid ? .distantPast : scheduledDep.addingTimeInterval(TimeInterval(dDelay * 60)),
                arr_time_eff: isFirst ? .distantPast : scheduledArr.addingTimeInterval(TimeInterval(aDelay * 60)),
                ref_time: scheduledArr
            ))
        }
    
        context.insert(Stop(id: train1.id, name: "Roma Termini", platform: "24", weather: "☀️ 14°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: time(6, 20), arr_time_id: .distantPast, dep_time_eff: time(6, 20), arr_time_eff: .distantPast, ref_time: time(6, 20)))
        context.insert(Stop(id: train1.id, name: "Milano Centrale", platform: "5", weather: "🌫️ 6°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 0, arr_delay: -2, dep_time_id: .distantPast, arr_time_id: time(8, 46), dep_time_eff: .distantPast, arr_time_eff: time(8, 44), ref_time: time(8, 46)))
        // The first leg of the day: it hands the journey over to 3224 at Savigliano,
        // so it has to arrive there before 3224 leaves at 9:51.
        context.insert(Stop(id: train3.id, name: "Saluzzo", platform: "1", weather: "🌧️ 7°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: time(9, 10), arr_time_id: .distantPast, dep_time_eff: time(9, 10), arr_time_eff: .distantPast, ref_time: time(9, 10)))
        context.insert(Stop(id: train3.id, name: "Savigliano", platform: "1AF", weather: "🌦️ 8°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 0, arr_delay: 3, dep_time_id: .distantPast, arr_time_id: time(9, 32), dep_time_eff: .distantPast, arr_time_eff: time(9, 35), ref_time: time(9, 32)))

        let seats = [
            Seat(id: UUID(), trainID: train2.id, name: "Pierpaolo", carriage: "1", number: "2D", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Davide", carriage: "1", number: "7B", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Andrea", carriage: "2", number: "8C", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Marco", carriage: "4", number: "10C", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Luca", carriage: "8", number: "10D", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Riccardo", carriage: "11", number: "11A", image: mockImageData),
            Seat(id: UUID(), trainID: train2.id, name: "Fabio", carriage: "12", number: "14B", image: mockImageData)
        ]
        seats.forEach { context.insert($0) }
    
        let fav1 = Favorite(
            id: UUID(), index: 0, identifier: train1.identifier, provider: train1.provider, logo: train1.logo, number: train1.number,
            stop_names: ["Roma Termini", "Milano Centrale"], stop_ref_times: [time(6, 20), time(8, 46)]
        )
        let fav2 = Favorite(
            id: UUID(), index: 1, identifier: train2.identifier, provider: train2.provider, logo: train2.logo, number: train2.number,
            stop_names: ["Cuneo", "Carmagnola"], stop_ref_times: [time(9, 24), time(10, 9)]
        )
        [fav1, fav2].forEach { context.insert($0) }

        // Journeys already travelled, so the Past list has something in it and the
        // profile's stat cards add up to something.
        func insertPastJourney(
            logo: String,
            number: String,
            from: String,
            to: String,
            daysAgo: Int,
            departure: (Int, Int),
            arrival: (Int, Int),
            arrivalDelay: Int,
            issue: String = ""
        ) {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            func at(_ hourMinute: (Int, Int)) -> Date {
                calendar.date(bySettingHour: hourMinute.0, minute: hourMinute.1, second: 0, of: day) ?? day
            }

            let isCancelled = !issue.isEmpty
            let train = Train(
                id: UUID(), logo: logo, number: number, identifier: "\(logo)\(number)",
                provider: "trenitalia", last_update_time: at(arrival),
                delay: isCancelled ? 0 : arrivalDelay, direction: to, issue: issue
            )
            context.insert(train)

            context.insert(Stop(
                id: train.id, name: from, platform: "", weather: "",
                is_selected: true, status: isCancelled ? 3 : 0,
                is_completed: !isCancelled, is_in_station: false,
                dep_delay: 0, arr_delay: 0,
                dep_time_id: at(departure), arr_time_id: .distantPast,
                dep_time_eff: at(departure), arr_time_eff: .distantPast,
                ref_time: at(departure)
            ))
            context.insert(Stop(
                id: train.id, name: to, platform: "", weather: "",
                is_selected: true, status: isCancelled ? 3 : 0,
                is_completed: !isCancelled, is_in_station: false,
                dep_delay: 0, arr_delay: isCancelled ? 0 : arrivalDelay,
                dep_time_id: .distantPast, arr_time_id: at(arrival),
                dep_time_eff: .distantPast,
                arr_time_eff: at(arrival).addingTimeInterval(TimeInterval(arrivalDelay * 60)),
                ref_time: at(arrival)
            ))
        }

        insertPastJourney(logo: "FR", number: "9640", from: "Torino Porta Nuova", to: "Milano Centrale",
                          daysAgo: 2, departure: (17, 0), arrival: (17, 55), arrivalDelay: 7)
        insertPastJourney(logo: "FR", number: "9512", from: "Milano Centrale", to: "Roma Termini",
                          daysAgo: 5, departure: (8, 10), arrival: (11, 15), arrivalDelay: 0)
        insertPastJourney(logo: "IC", number: "553", from: "Roma Termini", to: "Napoli Centrale",
                          daysAgo: 9, departure: (15, 35), arrival: (17, 25), arrivalDelay: 12)
        insertPastJourney(logo: "REG", number: "4021", from: "Torino Porta Nuova", to: "Cuneo",
                          daysAgo: 3, departure: (7, 20), arrival: (9, 5), arrivalDelay: 0,
                          issue: "Treno cancellato")

        let passes = [
            Pass(id: UUID(), name: "Abbonamento Mensile", start_date: Calendar.current.date(byAdding: .day, value: -15, to: Date())!, expiry_date: Calendar.current.date(byAdding: .day, value: 15, to: Date())!, is_principal: false, price: "62,00 €", image: mockImageData),
            Pass(id: UUID(), name: "Settimanale Studenti", start_date: Calendar.current.date(byAdding: .day, value: -9, to: Date())!, expiry_date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, is_principal: false, price: "19,50 €", image: mockImageData),
            Pass(id: UUID(), name: "Pass Regionale", start_date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!, expiry_date: Calendar.current.date(byAdding: .month, value: 3, to: Date())!, is_principal: true, price: "540,00 €", image: mockImageData)
        ]
        passes.forEach { context.insert($0) }

        return container
    }

    /// Milano Centrale → Roma Termini: a direct train, one with a change at Bologna,
    /// and one finished by a replacement bus.
    static func chooseTrainSolutions() -> [Solution] {
        let start = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!

        // mock solutions for Milano Centrale → Roma Termini
        let solutionsFetched: [Solution] = [
            // direct
            Solution(segments: [
                SolutionSegment(
                    origin: "Milano Centrale", destination: "Roma Termini",
                    departureTime: start, arrivalTime: start.addingTimeInterval(3 * 3600),
                    logo: "FR", number: "9612", stationCode: "S01700", isBus: false
                )
            ], price: 51.45),
            // with a connection in Bologna
            Solution(segments: [
                SolutionSegment(
                    origin: "Milano Centrale", destination: "Bologna Centrale",
                    departureTime: start.addingTimeInterval(900), arrivalTime: start.addingTimeInterval(900 + 64 * 60),
                    logo: "FR", number: "9613", stationCode: "S01700", isBus: false
                ),
                SolutionSegment(
                    origin: "Bologna Centrale", destination: "Roma Termini",
                    departureTime: start.addingTimeInterval(900 + 90 * 60), arrivalTime: start.addingTimeInterval(900 + 90 * 60 + 125 * 60),
                    logo: "IC", number: "605", stationCode: "S05043", isBus: false
                )
            ], price: 33.00),
            // train + replacement bus
            Solution(segments: [
                SolutionSegment(
                    origin: "Milano Centrale", destination: "Firenze S.M.N.",
                    departureTime: start.addingTimeInterval(1800), arrivalTime: start.addingTimeInterval(1800 + 110 * 60),
                    logo: "FR", number: "9615", stationCode: "S01700", isBus: false
                ),
                SolutionSegment(
                    origin: "Firenze S.M.N.", destination: "Roma Termini",
                    departureTime: start.addingTimeInterval(1800 + 140 * 60), arrivalTime: start.addingTimeInterval(1800 + 140 * 60 + 95 * 60),
                    logo: "BU", number: "FI451", stationCode: "S06421", isBus: true
                )
            ], price: 21.45)
        ]
        return solutionsFetched
    }
}
