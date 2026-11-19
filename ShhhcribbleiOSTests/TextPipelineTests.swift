import XCTest
@testable import ShhhcribbleiOS

final class TextPipelineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "customFillerWords")
    }

    // MARK: Filler words

    func testRemovesDefiniteFillers() {
        XCTAssertEqual(FillerWordFilter.filter("Um, I think uh we should go"), "I think we should go")
    }

    func testKeepsOrdinaryWords() {
        XCTAssertEqual(FillerWordFilter.filter("The umbrella is in the hall"), "The umbrella is in the hall")
    }

    func testCustomFillerWords() {
        UserDefaults.standard.set(["basically"], forKey: "customFillerWords")
        XCTAssertEqual(FillerWordFilter.filter("It is basically, done"), "It is done")
    }

    // MARK: Substitutions

    func testSubstitutionIsWholeWordAndCaseInsensitive() {
        let out = SubstitutionPass.apply("fontsake and Fontsakes", rules: ["fontsake": "Fontsake"])
        XCTAssertEqual(out, "Fontsake and Fontsakes")
    }

    func testEmptyRulesLeaveTextAlone() {
        XCTAssertEqual(SubstitutionPass.apply("hello", rules: [:]), "hello")
    }

    // MARK: Titles

    func testTitleIsFirstSentence() {
        XCTAssertEqual("Buy milk. Then call Ana.".autoTitle(), "Buy milk")
    }

    func testTitleTruncatesAtWordBoundary() {
        let long = String(repeating: "word ", count: 30)
        let title = long.autoTitle(maxLength: 20)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(title.count, 21)
    }

    func testEmptyTitleFallsBack() {
        XCTAssertEqual("   ".autoTitle(), "Untitled")
    }

    // MARK: Markdown detection

    func testMarkdownDetection() {
        XCTAssertTrue("# Heading\ntext".containsMarkdownSyntax)
        XCTAssertTrue("- item".containsMarkdownSyntax)
        XCTAssertFalse("Just a plain sentence.".containsMarkdownSyntax)
    }
}
