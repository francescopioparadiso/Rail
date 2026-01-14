import SwiftUI
import SwiftData

let appFontDesign: Font.Design = .rounded

enum Tab: Hashable {
    case past
    case today
}

struct ContentView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]

    // tab variables
    @State private var selectedTab: Tab = .today

    // MARK: - main view
    var body: some View {
        TabView(selection: $selectedTab) {
            PastView()
                .tabItem {
                    Label("Past", systemImage: "tray.full")
                }
                .tag(Tab.past)
            
            
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar.day.timeline.leading")
                }
                .tag(Tab.today)
        }
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
        }
    }
}
