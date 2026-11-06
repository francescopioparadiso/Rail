import SwiftUI
import SwiftData

/// App Store screenshots, taken by `scripts/screenshots.sh`.
///
/// Launched with `-rail-screenshot N`, a Debug build runs on the invented data of
/// `PreviewMockData` instead of the user's store, touches no network for the
/// journeys, and opens straight on screen N:
///
///   1 Today   2 a journey   3 From Email   4 Choose Train
///   5 Station board   6 Passes   7 Profile
///
/// Release builds never read the argument, so `scene` is always nil there.
enum ScreenshotMode {
    static let scene: Int? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-rail-screenshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }()

    static var isActive: Bool { scene != nil }
}

/// The main screen on the mock data, with whatever the scene needs on top of it,
/// presented the same way the app presents it.
struct ScreenshotRoot: View {
    let scene: Int

    private let solutions = PreviewMockData.chooseTrainSolutions()

    var body: some View {
        ContentView(usesMockMailbox: true, previewNow: PreviewMockData.moment)
            .sheet(isPresented: .constant(scene >= 3)) { sheet }
            .task {
                // the journey is pushed the way a tapped link pushes it
                guard scene == 2 else { return }
                try? await Task.sleep(for: .milliseconds(500))
                DeepLinkRouter.shared.open(trainID: PreviewMockData.detailsTrainID)
            }
    }

    @ViewBuilder
    private var sheet: some View {
        switch scene {
        case 3:
            EmailTrainImportView(autoScanOnAppear: false, previewTicketsAreReady: true)
        case 4:
            AddTrainView(
                previewView: .chooseTrain,
                searchType: .stations,
                fetching: .success,
                solutionsFetched: solutions,
                expandedSolutionID: solutions[1].id,
                selectedSolutionID: solutions[1].id
            )
        case 5:
            StationBoardView(initialStation: "Milano Centrale")
        case 6:
            PassView()
        default:
            ProfileView()
        }
    }
}
