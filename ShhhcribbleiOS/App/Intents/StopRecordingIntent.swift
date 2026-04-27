import AppIntents

struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Shhhcribble Recording"
    // Opens the app when tapped from a Live Activity. Required while
    // running under a free Personal Team without an App Group entitlement —
    // cross-process intent routing silently fails without it. Switch back
    // to `false` once the App Group is restored under a paid Apple
    // Developer Program account.
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    static var performer: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.performer?()
        return .result()
    }
}
