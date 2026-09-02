import SwiftUI
import SwiftData

/// Handles an incoming `rail://` journey: imports it, then tells the caller
/// which section it landed in so the list can be brought into view.
struct SharedTrainImport: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let onImported: (MainTab) -> Void

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard let payload = TrainSharing.payload(from: url),
                  let train = TrainSharing.importPayload(payload, into: modelContext)
            else { return }

            HapticFeedback.confirm()
            let departure = payload.stops.first?.time ?? Date()
            let isPast = departure < Calendar.current.startOfDay(for: Date())
            _ = train
            onImported(isPast ? .past : .today)
        }
    }
}

extension View {
    func handlesSharedTrains(onImported: @escaping (MainTab) -> Void) -> some View {
        modifier(SharedTrainImport(onImported: onImported))
    }
}
