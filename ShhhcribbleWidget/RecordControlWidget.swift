import AppIntents
import ShhhcribbleShared
import SwiftUI
import WidgetKit

struct RecordControlWidget: ControlWidget {
    static let kind = "com.shhhcribble.ios.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartFromControlIntent()) {
                Label("Record", systemImage: "waveform")
            }
        }
        .displayName("Shhhcribble")
        .description("Start a Shhhcribble recording.")
    }
}
