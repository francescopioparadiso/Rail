import SwiftUI
import SwiftData

let app_font_design: Font.Design = .rounded

enum current_tab: Hashable {
    case past
    case today
    case add
}

struct ContentView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var favorites: [Favorite]

    // tab variables
    @State private var selectedTab: current_tab = .today
    
    // sheet variables
    @State private var add_train_sheet = false
    @State private var add_favorite_sheet = false
    @State private var add_pass_sheet = false
    
    // favorites variables
    @State var favorites_fetched: [UUID: [String: Any]] = [:]
    @State var favoriteID_selected: UUID? = nil

    // MARK: - main view
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                Tab("Past", systemImage: "tray.full", value: .past) {
                    PastView()
                        .onAppear {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                }
                
                Tab("Today", systemImage: "calendar.day.timeline.leading", value: .today) {
                    TodayView()
                        .onAppear {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                }
                
                Tab("Add", systemImage: "plus", value: .add, role: .search) {
                    TodayView()
                        .onAppear {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            add_favorite_sheet = false
                            add_train_sheet = true
                            selectedTab = .today
                        }
                }
                
                    
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        add_favorite_sheet = true
                    } label: {
                        Image(systemName: "heart")
                    }
                    .tint(Color.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        add_pass_sheet = true
                    } label: {
                        Image(systemName: "qrcode")
                    }
                }
            }
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
            
            Task {
                let results = await fetch_favorites(favorites: favorites)
                self.favorites_fetched = results
            }
        }
        .sheet(isPresented: $add_train_sheet) {
            AddTrainView(add_favorite_sheet: add_favorite_sheet)
        }
        .sheet(isPresented: $add_favorite_sheet) {
            AddFavoriteView(
                favorites_fetched: $favorites_fetched,
                favoriteID_selected: $favoriteID_selected
            )
        }
        .sheet(isPresented: $add_pass_sheet) {
            AddPassView()
        }
        .onOpenURL { url in
            if url.scheme == "railapp" && url.host == "view-pass" {
                if !add_pass_sheet {
                    add_pass_sheet = true
                }
            }
        }
    }
}

// MARK: - previews
#Preview {
    // MARK: - SwiftData Setup
    let schema = Schema([Train.self, Stop.self, Seat.self, Favorite.self, Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    func time(_ hour: Int, _ min: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: min, second: 0, of: Date()) ?? .distantPast
    }
    
    let mockImageData = UIImage(named: "sample_code")?.pngData()
    
    // MARK: - Trains & Stops Data
    let train1 = Train(id: UUID(), logo: "ITALO", number: "9904", identifier: "IT9904", provider: "italo", last_update_time: Date(), delay: -2, direction: "Milano Centrale", issue: "")
    let train2 = Train(id: UUID(), logo: "REG", number: "3224", identifier: "REG3224", provider: "trenitalia", last_update_time: Date(), delay: 5, direction: "Carmagnola", issue: "Corsa terminata a Carmagnola per un guasto sulla linea.")
    let train3 = Train(id: UUID(), logo: "REG", number: "3223", identifier: "REG3223", provider: "trenitalia", last_update_time: Date(), delay: 0, direction: "Savigliano", issue: "")
    
    [train1, train2, train3].forEach { context.insert($0) }
    
    // Train 2 Journey Details (with delays and status variations)
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
    context.insert(Stop(id: train3.id, name: "Torino Porta Nuova", platform: "15", weather: "☁️ 9°C", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: time(12, 50), arr_time_id: .distantPast, dep_time_eff: time(12, 50), arr_time_eff: .distantPast, ref_time: time(12, 50)))
    context.insert(Stop(id: train3.id, name: "Savigliano", platform: "1AF", weather: "🌧️ 7°C", is_selected: true, status: 0, is_completed: false, is_in_station: true, dep_delay: 0, arr_delay: 5, dep_time_id: .distantPast, arr_time_id: time(14, 22), dep_time_eff: .distantPast, arr_time_eff: time(14, 27), ref_time: time(14, 22)))

    // MARK: - Seats Data
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
    
    // MARK: - Favorites Data
    let fav1 = Favorite(
        id: UUID(), index: 0, identifier: train1.identifier, provider: train1.provider, logo: train1.logo, number: train1.number,
        stop_names: ["Roma Termini", "Milano Centrale"], stop_ref_times: [time(6, 20), time(8, 46)]
    )
    let fav2 = Favorite(
        id: UUID(), index: 1, identifier: train2.identifier, provider: train2.provider, logo: train2.logo, number: train2.number,
        stop_names: ["Cuneo", "Carmagnola"], stop_ref_times: [time(9, 24), time(10, 9)]
    )
    [fav1, fav2].forEach { context.insert($0) }

    // MARK: - Passes Data
    let passes = [
        Pass(id: UUID(), name: "Abbonamento Mensile", expiry_date: Calendar.current.date(byAdding: .day, value: 15, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Settimanale Studenti", expiry_date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, is_principal: false, image: mockImageData),
        Pass(id: UUID(), name: "Pass Regionale", expiry_date: Calendar.current.date(byAdding: .month, value: 3, to: Date())!, is_principal: true, image: mockImageData)
    ]
    passes.forEach { context.insert($0) }

    return ContentView()
        .modelContainer(container)
}
