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

    /// Set by the app at launch. The argument says where the start came
    /// from: "shortcut" (Siri, Shortcuts, Back Tap, Action Button, which
    /// cannot be told apart) or "controlCenter".
    static var performer: (@Sendable (String) async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?("shortcut")
        return .result()
    }
}

// The Control Center button uses its own intent type so the note can record
// that it was started there. Hidden from Siri and Shortcuts: for people the
// one start action is StartRecordingIntent.
struct StartFromControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Shhhcribble Recording from Control Center"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await StartRecordingIntent.performer?("controlCenter")
        return .result()
    }
}
