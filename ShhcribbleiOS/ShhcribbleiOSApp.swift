import ShhcribbleShared
import SwiftUI

@main
struct ShhcribbleiOSApp: App {
    @StateObject private var status = TranscriptionStatus.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AudioSessionManager.shared.configure()
        AudioInterruptionObserver.shared.start()
        StopRecordingIntent.performer = {
            await TranscriptionService.shared.stopRecording()
        }
        Task.detached(priority: .userInitiated) {
            try? await TranscriptionService.shared.ensureModelLoaded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { RecordingOverlayView(status: status) }
                .animation(.easeInOut(duration: 0.18), value: status.isRecording)
                .onOpenURL { url in handle(url: url) }
                .onChange(of: scenePhase) { _, phase in
                    // When the user taps iOS's "← Back to X" pill, the scene
                    // transitions to .background. If we're mid-recording,
                    // stop & commit — the transcription Task keeps running
                    // under UIBackgroundModes=audio while iOS ferries the user
                    // back to the previous app.
                    if phase == .background && status.isRecording {
                        Task { await TranscriptionService.shared.stopRecording() }
                    }
                }
        }
    }

    private func handle(url: URL) {
        guard url.scheme?.lowercased() == "shhcribble" else { return }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()

        switch action {
        case "record":
            guard !status.isRecording else { return }
            // Flip synchronously so the overlay covers the launch flash before
            // the actor hop inside recordAndTranscribe can update it.
            status.isRecording = true
            status.launchedViaURL = true
            Task {
                do {
                    try await TranscriptionService.shared.recordAndTranscribe()
                } catch {
                    await MainActor.run {
                        status.isRecording = false
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
