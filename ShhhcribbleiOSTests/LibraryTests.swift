import XCTest
@testable import ShhhcribbleiOS

@MainActor
final class LibraryTests: XCTestCase {

    private func makeLibrary() -> Library { Library(backend: InMemoryBackend()) }

    func testInsertAddsNewestFirstWithAutoTitle() {
        let library = makeLibrary()
        library.insert(transcript: "First note. More.", duration: 3, trigger: .manual,
                       createdAt: Date(timeIntervalSince1970: 100))
        library.insert(transcript: "Second note", duration: 2, trigger: .shortcut,
                       createdAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(library.notes.map(\.title), ["Second note", "First note"])
        XCTAssertEqual(library.notes.first?.trigger, .shortcut)
    }

    func testInsertWithSameIdHappensOnce() {
        let library = makeLibrary()
        let id = UUID()
        XCTAssertTrue(library.insert(transcript: "From the recorder", duration: 5, trigger: .file, id: id))
        XCTAssertFalse(library.insert(transcript: "Fetched again", duration: 5, trigger: .file, id: id))
        XCTAssertEqual(library.notes.count, 1)
        XCTAssertEqual(library.notes.first?.transcript, "From the recorder")
    }

    func testAppendKeepsTitleAndAddsBlankLine() {
        let library = makeLibrary()
        let id = UUID()
        library.insert(transcript: "Start", duration: 1, trigger: .manual, id: id)
        library.append(transcript: "More", to: id)
        XCTAssertEqual(library.note(id: id)?.transcript, "Start\n\nMore")
        XCTAssertEqual(library.note(id: id)?.title, "Start")
    }

    func testAppendToMissingNoteDoesNothing() {
        let library = makeLibrary()
        library.append(transcript: "Lost", to: UUID())
        XCTAssertTrue(library.notes.isEmpty)
    }

    func testUpdateTagsAndDelete() {
        let library = makeLibrary()
        let id = UUID()
        library.insert(transcript: "Tag me", duration: 1, trigger: .manual, id: id)
        var note = library.note(id: id)!
        note.tags = ["work", "idea"]
        library.update(note)
        XCTAssertEqual(library.allTags, ["idea", "work"])
        library.delete(id: id)
        XCTAssertNil(library.note(id: id))
        XCTAssertTrue(library.allTags.isEmpty)
    }

    func testDeleteAll() {
        let library = makeLibrary()
        library.insert(transcript: "One", duration: 1, trigger: .manual)
        library.insert(transcript: "Two", duration: 1, trigger: .manual)
        library.deleteAll()
        XCTAssertTrue(library.notes.isEmpty)
    }
}
