import AVFoundation
import UIKit

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private(set) var isRunning = false

    /// Smoothed RMS level kept between callbacks for the envelope follower.
    /// Attack is instantaneous (max of incoming or decayed prior); release
    /// is a per-buffer decay so the bars trail off during pauses.
    private var smoothedLevel: Float = 0

    func start(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping (Float) -> Void = { _ in }
    ) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.smoothedLevel = 0

        AudioSessionManager.shared.configure()
        AudioSessionManager.shared.activate()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 2560, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            // Compute RMS on the first channel. Speech RMS is typically
            // ~0.005 (quiet) to ~0.15 (loud), so we scale ~6.5× to map a
            // full-throat speaker to ~1.0.
            if let ch = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                if count > 0 {
                    var sum: Float = 0
                    for i in 0..<count { sum += ch[i] * ch[i] }
                    let rms = (sum / Float(count)).squareRoot()
                    // Speech RMS is typically ~0.005 quiet to ~0.10 loud.
                    // Scale 12× so a normal speaking voice peaks near 1.0.
                    let scaled = min(1.0, rms * 12.0)
                    // Envelope: instant attack on peaks, steeper decay than
                    // before so the bars track real dynamics instead of
                    // smearing into a constant glow.
                    self.smoothedLevel = max(scaled, self.smoothedLevel * 0.78)
                    self.onLevel?(self.smoothedLevel)
                }
            }

            self.onBuffer?(buffer)
        }
        try engine.start()
        isRunning = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        onBuffer = nil
        onLevel = nil
        smoothedLevel = 0
    }
}
