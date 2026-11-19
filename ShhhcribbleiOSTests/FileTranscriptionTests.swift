import XCTest
@testable import ShhhcribbleiOS

/// Runs the real speech model on the spoken fixture clip. Needs the Parakeet
/// TDT v3 model, which is downloaded once per simulator or device (about
/// 480 MB), so the first run is slow and needs a network.
final class FileTranscriptionTests: XCTestCase {

    func testTranscribesSpokenClip() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "spoken-clip", withExtension: "wav")
        )
        let text = try await TranscriptionService.shared.transcribeFile(at: url).lowercased()
        XCTAssertTrue(text.contains("dentist"), "got: \(text)")
        XCTAssertTrue(text.contains("lazy dog"), "got: \(text)")
    }
}
