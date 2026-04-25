import AVFoundation
import UIKit

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRunning = false

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer

        AudioSessionManager.shared.configure()
        AudioSessionManager.shared.activate()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        print("[Shhhcribble] Mic format: \(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

        var bufferIndex = 0
        inputNode.installTap(onBus: 0, bufferSize: 2560, format: format) { [weak self] buffer, _ in
            bufferIndex += 1
            if bufferIndex == 1 || bufferIndex % 30 == 0 {
                if let ch = buffer.floatChannelData?[0] {
                    let count = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<count { sum += ch[i] * ch[i] }
                    let rms = sqrt(sum / Float(max(count, 1)))
                    print("[Shhhcribble] buf #\(bufferIndex) frames=\(count) rms=\(rms)")
                }
            }
            self?.onBuffer?(buffer)
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
    }
}
