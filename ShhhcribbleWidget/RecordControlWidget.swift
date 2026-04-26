import AppIntents
import ShhhcribbleShared
import SwiftUI
import WidgetKit

struct RecordControlWidget: ControlWidget {
    static let kind = "com.hendrivanniekerk.shhhcribble.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label {
                    Text("Record")
                } icon: {
                    Image("RecordIcon")
                }
            }
        }
        .displayName("Shhhcribble")
        .description("Start a Shhhcribble recording.")
    }
}
