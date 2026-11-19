import AppIntents

struct CancelRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Shhhcribble Recording"
    // See StopRecordingIntent: runs in the app's process, app stays put.
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
