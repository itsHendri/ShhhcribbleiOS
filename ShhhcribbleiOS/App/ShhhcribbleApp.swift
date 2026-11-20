import ShhhcribbleShared
import SwiftUI
import UIKit
import WidgetKit
import ShhhcribbleCore
import os

private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "app")

@main
struct ShhhcribbleApp: App {
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var appDelegate
    @StateObject private var status = TranscriptionStatus.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false

    init() {
        AudioSessionManager.shared.configure()
        AudioInterruptionObserver.shared.start()
        // Before launch finishes, so a tapped alert that started the app is
        // delivered. Reading the task list brings the alerts in step.
        ReminderScheduler.shared.configure()
        _ = TaskList.shared
        SyncService.shared.start()
        StopRecordingIntent.performer = {
            await TranscriptionService.shared.stopRecording()
        }
        CancelRecordingIntent.performer = {
            // A real abort: drops the audio, saves nothing.
            await TranscriptionService.shared.cancelRecording()
        }
        StartRecordingIntent.performer = { @MainActor source in
            let trigger = TriggerSource(rawValue: source) ?? .shortcut
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
                    try await service.recordAndTranscribe(trigger: trigger)
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
                    // The widget or the keyboard may have written to the
                    // library while the app was away.
                    if phase == .active {
                        SharedLibrary.store.reloadIfChangedElsewhere()
                        SyncService.shared.syncNow()
                    }
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
    }

    private func handle(url: URL) {
        // An audio file opened from Files or a share sheet: transcribe it
        // into a note.
        if url.isFileURL {
            Task { await TranscriptionService.shared.importAudioFile(url) }
            return
        }
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
                    try await TranscriptionService.shared.recordAndTranscribe(trigger: .shortcut)
                } catch {
                    await MainActor.run {
                        if status.phase == .recording { status.setPhase(.idle) }
                        status.launchedViaURL = false
                    }
                }
            }
        case "widget-record":
            // The widget's record button. Like the in-app button: it keeps
            // recording across app switches and stops on Stop.
            AppRouter.shared.tab = .notes
            guard !status.isRecording else { return }
            status.setPhase(.recording)
            Task {
                do {
                    try await TranscriptionService.shared.recordAndTranscribe(trigger: .widget)
                } catch {
                    await MainActor.run {
                        if status.phase == .recording { status.setPhase(.idle) }
                    }
                }
            }
        case "tasks":
            AppRouter.shared.tab = .tasks
        case "notes":
            AppRouter.shared.tab = .notes
        case "deleted":
            AppRouter.shared.tab = .notes
            AppRouter.shared.showingBin = true
        case "stop":
            status.launchedViaURL = true
            Task { await TranscriptionService.shared.stopRecording() }
        default:
            break
        }
    }
}

/// Only for iCloud: CKSyncEngine learns of changes from another device through
/// silent pushes, which need the app registered for remote notifications. It
/// handles the pushes itself; this asks iOS for them and nothing more.
final class SyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if SyncService.buildCanSync { application.registerForRemoteNotifications() }
        return true
    }
}
