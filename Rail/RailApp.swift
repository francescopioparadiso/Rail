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
        TrainActivityManager.shared.observeEnablement()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if TrainActivityDebug.isPreviewRequested {
                TrainActivityDebugScreen()
            } else {
                mainScene
            }
            #else
            mainScene
            #endif
        }
        .modelContainer(sharedModelContainer)
    }

    private var mainScene: some View {
        ContentView()
                #if DEBUG
                // `-rail-test-activity` puts a made-up journey on screen the moment
                // the app launches, so a simulator run can be looked at without
                // anyone having to tap a button.
                .task {
                    guard TrainActivityDebug.isLaunchTestRequested else { return }
                    // Clear the last run's, so repeated launches do not pile up and
                    // tip the island into its multiple-activity presentation.
                    await TrainActivityDebug.endAll()
                    await TrainActivityDebug.startTestActivityNow()
                }
                #endif
    }
}
