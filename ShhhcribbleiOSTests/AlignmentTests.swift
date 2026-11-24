import XCTest
import ShhhcribbleCore
@testable import ShhhcribbleiOS

/// The Mac and iPhone alignment picks of 2026-11-24: the list row's words,
/// grouping by day, and spoken meetings waiting in Tasks.
@MainActor
final class AlignmentTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testNotesAreGroupedByDayNewestFirst() {
        let now = at(24, 12)
        let notes = [at(24, 9), at(23, 19), at(23, 8), at(17, 10)].map {
            LibraryNote(transcript: "x", createdAt: $0, duration: 3, trigger: .manual)
        }
        let days = NoteDay.groups(of: notes, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(days.map(\.notes.count), [1, 2, 1])
        XCTAssertTrue(days[2].title.contains("17"), days[2].title)
    }

    func testRowWordsSayTimeSourceAndLength() {
        var note = LibraryNote(transcript: "Hello", createdAt: at(24, 13), duration: 8.2, trigger: .manual)
        XCTAssertTrue(NoteDay.meta(note).hasSuffix("· iPhone · 0:08"), NoteDay.meta(note))
        note.source = .typed
        note.duration = 0
        XCTAssertTrue(NoteDay.meta(note).hasSuffix("· Typed"), NoteDay.meta(note))
    }

    func testAMacTypedNoteReadsAsTyped() {
        let store = TranscriptStore(path: ":memory:")
        store.addNote(Note(text: "Typed on the Mac"))
        let backend = CoreBackend(store: store)
        XCTAssertEqual(backend.all().first?.source, .typed)
    }

    func testASpokenMeetingWaitsInTasksAndNotInNotes() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        let id = list.addMeeting(title: "Ana", start: at(24, 15), end: at(24, 16), allDay: false,
                                 spokenText: "Meeting, Ana Tuesday at three.", trigger: .manual, duration: 3)
        list.refresh()
        XCTAssertEqual(list.meetings.map(\.id), [id])
        XCTAssertTrue(CoreBackend(store: store).all().isEmpty)

        // Not a Meeting: a plain note, with the words as spoken.
        list.notAMeeting(id: id, text: "Meeting, Ana Tuesday at three.")
        list.refresh()
        XCTAssertTrue(list.meetings.isEmpty)
        XCTAssertEqual(CoreBackend(store: store).all().map(\.transcript), ["Meeting, Ana Tuesday at three."])
    }

    func testChangingAMeetingKeepsItWaiting() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        let id = list.addMeeting(title: "Ana", start: nil, end: nil, allDay: false,
                                 spokenText: nil, trigger: nil, duration: nil)
        list.changeMeeting(id: id, title: "Ana and Rui", start: at(25, 10), end: at(25, 11), allDay: false)
        list.refresh()
        XCTAssertEqual(list.meetings.first?.title, "Ana and Rui")
        XCTAssertEqual(list.meetings.first?.start, at(25, 10))
    }

    func testASummaryToDoIsAddedOnce() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        let noteID = UUID()
        XCTAssertFalse(list.isInTasks(noteID: noteID, item: "Email Anna"))
        let first = list.addFromSummary(noteID: noteID, item: "Email Anna")
        let second = list.addFromSummary(noteID: noteID, item: "Email Anna")
        XCTAssertEqual(first, second)
        XCTAssertTrue(list.isInTasks(noteID: noteID, item: "Email Anna"))
        XCTAssertEqual(store.notes.filter(\.isTask).count, 1)
    }
}
