import XCTest
import ShhhcribbleCore
@testable import ShhhcribbleiOS

/// The library seam on the real shared store, in memory.
@MainActor
final class CoreBackendTests: XCTestCase {

    private func make() -> (TranscriptStore, Library) {
        let store = TranscriptStore(path: ":memory:")
        return (store, Library(backend: CoreBackend(store: store)))
    }

    func testInsertWritesAPhoneNoteWithItsTriggerAndLength() {
        let (store, library) = make()
        let id = UUID()
        XCTAssertTrue(library.insert(transcript: "Buy milk. Then call Ana.", duration: 4.5,
                                     trigger: .controlCenter, id: id, rawTranscript: "um buy milk then call ana"))
        let row = store.notes.first { $0.id == id }
        XCTAssertEqual(row?.text, "Buy milk. Then call Ana.")
        XCTAssertEqual(row?.origin, .phone)
        XCTAssertEqual(row?.originDetail, "controlCenter")
        XCTAssertEqual(row?.durationSec, 4.5)
        XCTAssertEqual(row?.rawText, "um buy milk then call ana")
        XCTAssertEqual(library.note(id: id)?.title, "Buy milk")
        XCTAssertEqual(library.note(id: id)?.trigger, .controlCenter)
    }

    func testSameIdIsSavedOnce() {
        let (store, library) = make()
        let id = UUID()
        XCTAssertTrue(library.insert(transcript: "From the recorder", duration: 5, trigger: .file, id: id))
        XCTAssertFalse(library.insert(transcript: "Fetched again", duration: 5, trigger: .file, id: id))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(library.notes.count, 1)
    }

    func testEditingTextClearsTheMacStylingAndKeepsTags() {
        let (store, library) = make()
        var row = Note(text: "Styled on the Mac")
        row.richText = Data([1, 2, 3])
        store.addNote(row)
        library.reload()

        var note = library.note(id: row.id)!
        note.tags = ["work"]
        library.update(note)
        XCTAssertNotNil(store.notes.first?.richText, "a tag change must not drop the styling")

        note.transcript = "Edited on the phone"
        library.update(note)
        XCTAssertNil(store.notes.first?.richText)
        XCTAssertEqual(store.notes.first?.text, "Edited on the phone")
        XCTAssertEqual(store.notes.first?.tags, ["work"])
    }

    func testUndoRestoresTheWholeRowIncludingMacStyling() {
        let (store, library) = make()
        var row = Note(text: "Styled on the Mac")
        row.richText = Data([9, 9])
        row.summary = "A summary"
        store.addNote(row)
        library.reload()
        library.delete(id: row.id)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(library.undoLastDelete(), 1)
        XCTAssertEqual(store.notes.first?.richText, Data([9, 9]))
        XCTAssertEqual(store.notes.first?.summary, "A summary")
        XCTAssertEqual(store.notes.first?.createdAt, row.createdAt)
    }

    func testTasksStayOutOfTheNotesList() {
        let (store, library) = make()
        store.addTask(text: "Call the dentist")
        library.insert(transcript: "A plain note", duration: 1, trigger: .manual)
        library.reload()
        XCTAssertEqual(library.notes.map(\.transcript), ["A plain note"])
    }

    func testDeleteAllLeavesTasksAlone() {
        let (store, library) = make()
        store.addTask(text: "Keep me")
        library.insert(transcript: "One", duration: 1, trigger: .manual)
        library.insert(transcript: "Two", duration: 1, trigger: .manual)
        library.deleteAll()
        XCTAssertTrue(library.notes.isEmpty)
        XCTAssertEqual(store.notes.map(\.text), ["Keep me"])
    }

    func testAWriteFromElsewhereReachesTheLibrary() async {
        let (store, library) = make()
        store.addNote(Note(text: "Made on the Mac"))
        // The backend hears the store on the next main-queue turn.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(library.notes.map(\.transcript), ["Made on the Mac"])
    }

    func testOldVocabularyMovesIntoTheDictionaryOnce() throws {
        let store = TranscriptStore(path: ":memory:")
        let defaults = UserDefaults(suiteName: "vocab-\(UUID().uuidString)")!
        defaults.set(["GitHub"], forKey: "customHotwords")
        defaults.set(try JSONEncoder().encode(["font sake": "Fontsake"]), forKey: "substitutionRules")

        VocabularyMigration.runIfNeeded(into: store, defaults: defaults)
        VocabularyMigration.runIfNeeded(into: store, defaults: defaults)

        XCTAssertEqual(store.dictionaryEntries.map(\.phrase), ["font sake", "GitHub"])
        let vocabulary = Vocabulary()
        vocabulary.set(store.dictionaryEntries)
        XCTAssertEqual(vocabulary.apply(to: "push font sake to github"), "push Fontsake to GitHub")
    }
}

@MainActor
final class SummaryAndFinishTests: XCTestCase {

    func testASummaryIsStoredWithoutCountingAsAnEdit() {
        let store = TranscriptStore(path: ":memory:")
        let library = Library(backend: CoreBackend(store: store))
        let id = UUID()
        library.insert(transcript: "We agreed I will send the invoice on Friday.", duration: 4, trigger: .manual, id: id,
                       createdAt: Date(timeIntervalSince1970: 1_000))
        let before = store.notes.first?.modifiedAt

        library.saveSummary(
            id: id, summary: "Invoice goes out Friday.",
            items: [NoteActionItem(text: "Send the invoice", quote: "I will send the invoice on Friday", owner: "me")]
        )

        XCTAssertEqual(store.notes.first?.summary, "Invoice goes out Friday.")
        XCTAssertEqual(store.notes.first?.actionItems.first?.quote, "I will send the invoice on Friday")
        XCTAssertEqual(store.notes.first?.modifiedAt, before)
        library.reload()
        XCTAssertEqual(library.note(id: id)?.actionItems.map(\.text), ["Send the invoice"])
        XCTAssertNotNil(library.note(id: id)?.summaryGeneratedAt)
    }

    func testWithCleanupOffTheDictionaryRunsThenTheFillerFilter() async {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: TextFinisher.cleanupKey)
        defaults.set(false, forKey: TextFinisher.cleanupKey)
        defer { defaults.set(old, forKey: TextFinisher.cleanupKey) }
        Vocabulary.shared.set([DictionaryEntry(phrase: "font sake", replacement: "Fontsake")])
        defer { Vocabulary.shared.set([]) }

        let finished = await TextFinisher.finish("  um, push font sake today  ")
        XCTAssertEqual(finished.text, "push Fontsake today")
        XCTAssertFalse(finished.cleaned)
    }

    func testNothingHeardStaysEmpty() async {
        let finished = await TextFinisher.finish("   ")
        XCTAssertEqual(finished.text, "")
    }
}
