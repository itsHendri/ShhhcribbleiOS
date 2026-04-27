import ShhhcribbleShared
import SwiftData
import SwiftUI
import os

private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "app")

@main
struct ShhhcribbleApp: App {
    @StateObject private var status = TranscriptionStatus.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AudioSessionManager.shared.configure()
        AudioInterruptionObserver.shared.start()
        diagLog.notice("ShhhcribbleApp.init wiring performers")
        StopRecordingIntent.performer = {
            diagLog.notice("StopRecordingIntent performer FIRING")
            await TranscriptionService.shared.stopRecording()
            diagLog.notice("StopRecordingIntent performer COMPLETED")
        }
        CancelRecordingIntent.performer = {
            // Until Sprint 2 wires a real abort path (drop audio, skip
            // SwiftData write, restore clipboard), Cancel from the Live
            // Activity behaves identically to Stop.
            await TranscriptionService.shared.stopRecording()
        }
        StartRecordingIntent.performer = {
            let service = TranscriptionService.shared
            if await service.isRecording {
                await service.stopRecording()
            } else {
                // Trigger source attribution is best-effort — a single intent
                // can't tell whether it was fired from Control Center, Siri,
                // Shortcuts, or AppShortcuts. Refine with per-source intents
                // in a later sprint if attribution becomes important.
                try? await service.recordAndTranscribe(trigger: .manual)
            }
        }
        Task.detached(priority: .userInitiated) {
            try? await TranscriptionService.shared.ensureModelLoaded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { RecordingOverlayView(status: status) }
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: status.overlayVisible)
                .onOpenURL { url in handle(url: url) }
                .onChange(of: scenePhase) { _, phase in
                    // Only auto-stop on backgrounding when the recording was
                    // launched via URL scheme (e.g. Back Tap → Shortcut → app
                    // launches → user taps the "← Back to X" pill iOS shows
                    // at top-left). In that flow the back-pill IS the stop
                    // button, and we want the transcript to land on the
                    // clipboard before iOS ferries the user back.
                    //
                    // For recordings launched in-app (play button), keep
                    // recording across app switches — that's the whole point
                    // of background audio + the Live Activity. The user stops
                    // via the Live Activity's Stop button or by returning to
                    // the app.
                    if phase == .background
                        && status.isRecording
                        && status.launchedViaURL {
                        Task { await TranscriptionService.shared.stopRecording() }
                    }
                }
        }
        .modelContainer(NotesRepository.shared.container)
    }

    private func handle(url: URL) {
        guard url.scheme?.lowercased() == "shhhcribble" else { return }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()

        switch action {
        case "record":
            guard !status.isRecording else { return }
            // Flip synchronously so the overlay covers the launch flash before
            // the actor hop inside recordAndTranscribe can update it.
            status.setPhase(.recording)
            status.launchedViaURL = true
            Task {
                do {
                    try await TranscriptionService.shared.recordAndTranscribe()
                } catch {
                    await MainActor.run {
                        if status.phase == .recording { status.setPhase(.idle) }
                        status.launchedViaURL = false
                    }
                }
            }
        case "stop":
            status.launchedViaURL = true
            Task { await TranscriptionService.shared.stopRecording() }
        default:
            break
        }
    }
}
