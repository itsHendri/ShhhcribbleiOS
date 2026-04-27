import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private init() {}

    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Politely release any prior owner first. When recording launches
            // via Siri, Siri's audio session can still be active during its
            // dismissal animation; without this deactivation our subsequent
            // setActive(true) silently fails to take ownership of the mic
            // and the engine captures no audio.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        } catch {
            print("[Shhhcribble] AudioSession configure failed: \(error)")
        }
    }

    /// Activates the session. Retries once after a short delay because the
    /// first activation can fail if another audio session (notably Siri) is
    /// still releasing the mic when we launch via an AppIntent.
    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
        } catch {
            print("[Shhhcribble] AudioSession activate failed (retrying): \(error)")
            Thread.sleep(forTimeInterval: 0.3)
            do {
                try session.setActive(true, options: [])
            } catch {
                print("[Shhhcribble] AudioSession activate retry failed: \(error)")
            }
        }
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }
}
