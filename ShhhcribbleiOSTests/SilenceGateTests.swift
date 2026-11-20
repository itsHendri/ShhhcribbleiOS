import AVFoundation
import XCTest
@testable import ShhhcribbleiOS

final class SilenceGateTests: XCTestCase {

    private func buffer(seconds: Double, amplitude: Float, rate: Double = 16_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * rate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let data = b.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = amplitude * sin(Float(i) * 2 * .pi * 220 / Float(rate))
        }
        return b
    }

    func testRoomNoiseIsNotSpeech() {
        var gate = SilenceGate()
        for _ in 0..<40 { gate.observe(buffer(seconds: 0.05, amplitude: 0.003)) }
        XCTAssertEqual(gate.seconds, 2, accuracy: 0.01)
        XCTAssertFalse(gate.heardSpeech)
    }

    func testAClickIsNotSpeech() {
        var gate = SilenceGate()
        gate.observe(buffer(seconds: 0.05, amplitude: 0.3))
        for _ in 0..<30 { gate.observe(buffer(seconds: 0.05, amplitude: 0.003)) }
        XCTAssertFalse(gate.heardSpeech)
    }

    func testAShortQuietWordOpensTheGate() {
        var gate = SilenceGate()
        for _ in 0..<30 { gate.observe(buffer(seconds: 0.05, amplitude: 0.003)) }
        for _ in 0..<4 { gate.observe(buffer(seconds: 0.05, amplitude: 0.02)) }
        XCTAssertTrue(gate.heardSpeech)
    }

    func testTooShortIsSkippedEvenWhenLoud() {
        var gate = SilenceGate()
        gate.observe(buffer(seconds: 0.3, amplitude: 0.2))
        XCTAssertFalse(gate.heardSpeech)
    }

    func testResetClearsTheLastRecording() {
        var gate = SilenceGate()
        gate.observe(buffer(seconds: 1, amplitude: 0.2))
        XCTAssertTrue(gate.heardSpeech)
        gate.reset()
        XCTAssertFalse(gate.heardSpeech)
        XCTAssertEqual(gate.peakRMS, 0)
    }

    /// The spoken test clip, read at its real level, must pass.
    func testTheSpokenClipPasses() throws {
        let url = Bundle(for: Self.self).url(forResource: "spoken-clip", withExtension: "wav")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/spoken-clip.wav")
        let file = try AVAudioFile(forReading: url)
        let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: b)
        var gate = SilenceGate()
        gate.observe(b)
        XCTAssertTrue(gate.heardSpeech, "peak \(gate.peakRMS)")
    }
}
