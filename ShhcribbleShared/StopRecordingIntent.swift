import AppIntents

public struct StopRecordingIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop Shhcribble Recording"
    public static var openAppWhenRun: Bool = false
    public static var isDiscoverable: Bool = false

    public static var performer: (@Sendable () async -> Void)?

    public init() {}

    public func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
