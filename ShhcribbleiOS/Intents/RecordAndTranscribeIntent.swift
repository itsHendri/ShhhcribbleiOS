import AppIntents

@available(iOS 18.0, *)
struct RecordAndTranscribeIntent: AppIntent {
    static var title: LocalizedStringResource = "Shhcribble: Record & Transcribe"
    static var description = IntentDescription(
        "Record audio and copy the transcription to the clipboard. Triggering while recording stops and copies immediately."
    )
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        let service = TranscriptionService.shared
        if await service.isRecording {
            await service.stopRecording()
        } else {
            try await service.recordAndTranscribe()
        }
        return .result()
    }
}

@available(iOS 18.0, *)
struct ShhcribbleAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordAndTranscribeIntent(),
            phrases: [
                "Record with \(.applicationName)",
                "Transcribe with \(.applicationName)",
            ],
            shortTitle: "Record & Transcribe",
            systemImageName: "mic.fill"
        )
    }
}
