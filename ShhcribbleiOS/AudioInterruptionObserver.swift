import AVFoundation
import Foundation

final class AudioInterruptionObserver {
    static let shared = AudioInterruptionObserver()
    private init() {}

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            print("[Shhcribble] Audio session interrupted — stopping")
            Task { await TranscriptionService.shared.stopRecording() }
        case .ended:
            break
        @unknown default:
            break
        }
    }
}
