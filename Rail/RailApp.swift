import SwiftUI
import SwiftData

@main
struct RailApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try SharedSwiftData.makeAppContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        StationLookup.warmUp()
        NotificationManager.shared.registerDelegate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
