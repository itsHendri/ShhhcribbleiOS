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

    func testAppendAddsBlankLineAndTitleStaysTheFirstLine() {
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

    func testUndoBringsBackADeletedNote() {
        let library = makeLibrary()
        let id = UUID()
        library.insert(transcript: "Keep me", duration: 1, trigger: .manual, id: id)
        library.delete(id: id)
        XCTAssertNil(library.note(id: id))
        XCTAssertEqual(library.undoLastDelete(), 1)
        XCTAssertEqual(library.note(id: id)?.transcript, "Keep me")
        XCTAssertEqual(library.undoLastDelete(), 0, "undo works once")
    }

    func testUndoAfterClearAllBringsBackEverything() {
        let library = makeLibrary()
        library.insert(transcript: "One", duration: 1, trigger: .manual)
        library.insert(transcript: "Two", duration: 1, trigger: .manual)
        library.deleteAll()
        XCTAssertEqual(library.undoLastDelete(), 2)
        XCTAssertEqual(library.notes.count, 2)
    }

    func testDeletingSeveralIsOneUndo() {
        let library = makeLibrary()
        let a = UUID(), b = UUID(), c = UUID()
        for (id, t) in [(a, "A"), (b, "B"), (c, "C")] {
            library.insert(transcript: t, duration: 1, trigger: .manual, id: id)
        }
        library.delete(ids: [a, c])
        XCTAssertEqual(library.notes.map(\.id), [b])
        XCTAssertEqual(library.trashed.count, 2)
        XCTAssertEqual(library.undoLastDelete(), 2)
        XCTAssertEqual(library.notes.count, 3)
    }
}
