import AppIntents

struct CancelRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Shhhcribble Recording"
    // See StopRecordingIntent for why this is `true`. Same Personal Team
    // limitation. Restore to `false` when App Group is back.
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
