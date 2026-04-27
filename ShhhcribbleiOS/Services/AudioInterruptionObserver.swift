import AVFoundation
import Foundation
import os

private let diagLog = Logger(subsystem: "com.shhhcribble.diag", category: "audio")

final class AudioInterruptionObserver {
    static let shared = AudioInterruptionObserver()
    private init() {}

    /// Set when a recording starts. Interruptions arriving within
    /// ``handoffGrace`` of this timestamp are ignored — the typical case is
    /// the audio-session handoff right after Siri triggers our intent: Siri
    /// releases the mic, our session activates, and a transient `.began`
    /// interruption fires as the contexts swap. Treating that as a real
    /// interruption killed Siri-launched recordings after ~1 s. Real
    /// interruptions (phone calls, alarms) arrive well outside this window.
    private var recordingStartedAt: Date?
    private let handoffGrace: TimeInterval = 1.5

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    func recordingDidStart() {
        recordingStartedAt = Date()
    }

    func recordingDidStop() {
        recordingStartedAt = nil
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            if let started = recordingStartedAt,
               Date().timeIntervalSince(started) < handoffGrace {
                diagLog.notice("Audio interruption .began ignored (within Siri handoff grace)")
                return
            }
            diagLog.notice("Audio interruption .began — stopping recording")
            Task { await TranscriptionService.shared.stopRecording() }
        case .ended:
            break
        @unknown default:
            break
        }
    }
}
