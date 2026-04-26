import AppIntents

// Shared intent so both the main app (Siri/Shortcuts donations) and the
// widget extension (Control Center button) can invoke it. The main app sets
// the static `performer` on launch — calling from the widget routes through
// `openAppWhenRun: true` and the main app's perform completes the work.
public struct StartRecordingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Shhhcribble Recording"
    public static var description = IntentDescription(
        "Start a Shhhcribble recording. Triggering again while recording stops and saves the note."
    )
    public static var openAppWhenRun: Bool = true

    public static var performer: (@Sendable () async -> Void)?

    public init() {}

    public func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
