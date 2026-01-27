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
    // memory containers
    let schema = Schema([Train.self, Stop.self, Seat.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    let context = container.mainContext
    
    // mock data
    let trainToday = Train(
        id: UUID(),
        logo: "FR",
        number: "9612",
        identifier: "FR9612",
        provider: "trenitalia",
        last_update_time: Date(),
        delay: 5,
        direction: "Milano Centrale",
        seats: [],
        issue: ""
    )
    
    let trainPast = Train(
        id: UUID(),
        logo: "ITALO",
        number: "8901",
        identifier: "IT8901",
        provider: "italo",
        last_update_time: Date().addingTimeInterval(-172800),
        delay: 0,
        direction: "Roma Termini",
        seats: [],
        issue: ""
    )
    
    context.insert(trainToday)
    context.insert(trainPast)
    
    let stop1 = Stop(
        id: trainToday.id,
        name: "Torino Porta Nuova",
        platform: "3",
        weather: "sun.max",
        is_selected: true,
        status: 0,
        is_completed: true,
        is_in_station: false,
        dep_delay: 0,
        arr_delay: 0,
        dep_time_id: Date(),
        arr_time_id: Date(),
        dep_time_eff: Date(),
        arr_time_eff: Date(),
        ref_time: Date()
    )
    
    let stop2 = Stop(
        id: trainToday.id,
        name: "Milano Centrale",
        platform: "12",
        weather: "cloud.rain",
        is_selected: true,
        status: 0,
        is_completed: false,
        is_in_station: true,
        dep_delay: 5,
        arr_delay: 5,
        dep_time_id: Date().addingTimeInterval(3600),
        arr_time_id: Date().addingTimeInterval(3600),
        dep_time_eff: Date().addingTimeInterval(3900),
        arr_time_eff: Date().addingTimeInterval(3900),
        ref_time: Date().addingTimeInterval(3600)
    )
    
    context.insert(stop1)
    context.insert(stop2)
    
    // view
    return ContentView()
        .modelContainer(container)
}
