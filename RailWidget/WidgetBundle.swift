import WidgetKit
import SwiftUI

@main
struct RailWidgets: WidgetBundle {
    var body: some Widget {
        PassWidget()
        TicketWidget()
        TrainWidget()
    }
}
