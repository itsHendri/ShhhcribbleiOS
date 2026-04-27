import AppIntents

struct ShhhcribbleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Record with \(.applicationName)",
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
    }
}
