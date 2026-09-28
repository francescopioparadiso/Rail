import SwiftUI
import SwiftData

/// The typeface the whole app is set in. Applied once at the root, so every view
/// inherits it; pass it to `.fontDesign(_:)` wherever a view needs to set it again,
/// like a sheet or a view drawn outside the window's hierarchy.
///
/// SF Compact Rounded is not one of the choices: iOS ships it, but keeps it for
/// the system's own use and offers no API to pick it.
let appFontDesign: Font.Design = .rounded

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
            mainScene
        }
        .modelContainer(sharedModelContainer)
    }

    private var mainScene: some View {
        ContentView()
                .fontDesign(appFontDesign)
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
