import SwiftUI
import SwiftData

let appFontDesign: Font.Design = .rounded

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    private enum Tab: Hashable {
        case passati
        case oggi
        case aggiungi
    }

    @State private var selectedTab: Tab = .oggi

    var body: some View {
        TabView(selection: $selectedTab) {
            PastView()
                .tabItem {
                    Label("Past", systemImage: "tray.full")
                }
                .tag(Tab.passati)
            
            
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar.day.timeline.leading")
                }
                .tag(Tab.oggi)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Train.self, Stop.self], inMemory: true)
}
