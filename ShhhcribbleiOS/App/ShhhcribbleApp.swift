import ShhhcribbleShared
import SwiftData
import SwiftUI
import os

private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "app")

@main
struct ShhhcribbleApp: App {
    @StateObject private var status = TranscriptionStatus.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false

    init() {
        AudioSessionManager.shared.configure()
        AudioInterruptionObserver.shared.start()
        StopRecordingIntent.performer = {
            await TranscriptionService.shared.stopRecording()
        }
        CancelRecordingIntent.performer = {
            // Cancel from the Live Activity currently behaves identically
            // to Stop (commits the recording). Real abort lives in the
            // in-app Cancel button via TranscriptionService.cancelRecording.
            await TranscriptionService.shared.stopRecording()
        }
        StartRecordingIntent.performer = { @MainActor in
            let service = TranscriptionService.shared
            let status = TranscriptionStatus.shared
            if status.isRecording {
                Task.detached { await service.stopRecording() }
                return
            }
            // Flip the overlay synchronously so it covers the launch flash
            // before the actor hop inside recordAndTranscribe can run. Same
            // pattern as the URL-scheme handler in `handle(url:)`.
            status.setPhase(.recording)
            // Fire-and-forget: awaiting recordAndTranscribe here would keep
            // Siri's "Working…" panel up for the whole recording, which
            // absorbs touches and makes Stop / Cancel inert.
            Task.detached(priority: .userInitiated) {
                do {
                    try await service.recordAndTranscribe(trigger: .manual)
                } catch {
                    let msg = String(describing: error)
                    diagLog.error("recordAndTranscribe threw \(msg, privacy: .public)")
                    await MainActor.run {
                        status.setPhase(.error(.other(msg)))
                    }
                }
            }
        }
        Task.detached(priority: .userInitiated) {
            try? await TranscriptionService.shared.ensureModelLoaded()
        }
        // Sweep up any Live Activities that survived a prior crash or kill —
        // without this they accumulate as ghost banners across launches.
        Task { @MainActor in
            ShhhcribbleActivityManager.shared.reapOrphanedActivities()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { RecordingOverlayView(status: status) }
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: status.overlayVisible)
                .onOpenURL { url in handle(url: url) }
                .fullScreenCover(isPresented: Binding(
                    get: { !onboardingComplete },
                    set: { _ in /* dismissal happens via the onboarding "Get Started" / Skip buttons flipping the flag */ }
                )) {
                    OnboardingView()
                }
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
