import AppIntents
import os

private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "intent")

public struct StopRecordingIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop Shhhcribble Recording"
    // Opens the app when tapped from a Live Activity. Required while
    // running under a free Personal Team without an App Group entitlement —
    // cross-process intent routing silently fails without it. Switch back
    // to `false` once the App Group is restored under a paid Apple
    // Developer Program account.
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = false

    public static var performer: (@Sendable () async -> Void)?

    public init() {}

    public func perform() async throws -> some IntentResult {
        diagLog.notice("StopRecordingIntent.perform invoked, performer=\(Self.performer == nil ? "nil" : "set", privacy: .public)")
        await Self.performer?()
        diagLog.notice("StopRecordingIntent.perform returned")
        return .result()
    }
}
