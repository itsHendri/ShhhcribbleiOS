import ActivityKit
import AppIntents
import ShhhcribbleShared
import SwiftUI
import WidgetKit

struct ShhhcribbleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShhhcribbleActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.red.opacity(0.15))
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.status == .recording ? "Recording…" : "Stopping…")
                        .font(.subheadline.bold())
                    if !context.state.snippet.isEmpty {
                        Text(context.state.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .padding(10)
                        .background(Circle().fill(.red))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopRecordingIntent()) {
                        Image(systemName: "stop.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status == .recording ? "Recording" : "Stopping")
                        .font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.snippet.isEmpty {
                        Text(context.state.snippet)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            } compactTrailing: {
                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            }
        }
    }
}

