import SwiftUI
import SwiftData

@main
struct RailApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Train.self,
            Stop.self,
            Seat.self,
            Favorite.self,
            Pass.self
        ])
        
        let groupIdentifier = "group.com.francescoparadis.Rail"
        
        let modelConfiguration: ModelConfiguration
        
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let databaseURL = groupURL.appendingPathComponent("default.store")
            
            modelConfiguration = ModelConfiguration(
                groupIdentifier,
                schema: schema,
                url: databaseURL,
                allowsSave: true
            )
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
