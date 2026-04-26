import AppIntents

public struct CancelRecordingIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Cancel Shhhcribble Recording"
    // See StopRecordingIntent for why this is `true`. Same Personal Team
    // limitation. Restore to `false` when App Group is back.
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = false

    public static var performer: (@Sendable () async -> Void)?

    public init() {}

    public func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
