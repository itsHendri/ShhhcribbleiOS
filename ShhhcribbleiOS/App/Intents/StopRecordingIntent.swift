import AppIntents

struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Shhhcribble Recording"
    // A LiveActivityIntent runs in the app's process without bringing the
    // app forward, so Stop works from the lock screen without unlocking.
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
