import AVFoundation

/// Decides whether a recording held any speech before the speech model sees
/// it.
///
/// Parakeet always returns its most likely text, and on near-silence that is
/// a common short word ("Yeah.", "Okay.", "Recording"). The model cannot be
/// told not to guess, so the app does not ask it: a recording that never
/// rose above room noise, or is shorter than half a second, is "No speech
/// detected" without a transcription. The Mac app has the same half-second
/// minimum.
///
/// Loudness is the RMS of each buffer the microphone delivers (tens of
/// milliseconds). The gate opens when buffers above the threshold add up to
/// `minimumLoudSeconds`: a word lasts that long, a click or a bump does not.
/// The values are set low on purpose and err towards transcribing.
struct SilenceGate {
    /// RMS at or above this counts as sound worth transcribing. About
    /// -44 dBFS: well above a quiet room on the iPhone's microphone in
    /// measurement mode, well below speech at arm's length.
    static let threshold: Float = 0.006
    /// Shorter recordings are skipped whatever their level.
    static let minimumSeconds: Double = 0.5
    /// Time above the threshold needed to count as speech.
    static let minimumLoudSeconds: Double = 0.15

    private(set) var peakRMS: Float = 0
    /// The quietest buffer: roughly the room's noise floor.
    private(set) var floorRMS: Float = .greatestFiniteMagnitude
    private(set) var seconds: Double = 0
    private(set) var loudSeconds: Double = 0

    var heardSpeech: Bool {
        seconds >= Self.minimumSeconds && loudSeconds >= Self.minimumLoudSeconds
    }

    mutating func reset() {
        peakRMS = 0
        floorRMS = .greatestFiniteMagnitude
        seconds = 0
        loudSeconds = 0
    }

    mutating func observe(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let rate = buffer.format.sampleRate
        guard rate > 0, let channel = buffer.floatChannelData?[0] else { return }
        // Long buffers (a file, the debug clip) are judged in 50 ms slices,
        // so they count the same as the microphone's short ones.
        let slice = max(1, Int(rate * 0.05))
        var start = 0
        while start < frames {
            let count = min(slice, frames - start)
            let level = Self.rms(UnsafeBufferPointer(start: channel + start, count: count))
            let duration = Double(count) / rate
            seconds += duration
            peakRMS = max(peakRMS, level)
            floorRMS = min(floorRMS, level)
            if level >= Self.threshold { loudSeconds += duration }
            start += count
        }
    }

    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}
