import AppIntents

// Shared intent: the main app sets the static `performer` on launch. The
// widget extension compiles its own copy (multi-target source membership)
// for the Control Center button; iOS routes invocations to the main app via
// `openAppWhenRun: true` and the main app's perform body completes the work.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Shhhcribble Recording"
    static var description = IntentDescription(
        "Start a Shhhcribble recording. Triggering again while recording stops and saves the note."
    )
    static var openAppWhenRun: Bool = true

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
