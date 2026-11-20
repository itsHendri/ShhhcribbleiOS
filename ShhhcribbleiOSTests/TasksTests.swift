import XCTest
import ShhhcribbleCore
@testable import ShhhcribbleiOS

@MainActor
final class TasksTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return c
    }()

    /// Thursday 19 November 2026, 10:00 in Lisbon.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: The list

    func testTasksAreSortedIntoTheirSections() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        list.add(text: "Invoice", dueAt: at(18, 17))
        list.add(text: "Dentist", dueAt: at(19, 11, 30))
        list.add(text: "Inspection", dueAt: at(20, 9))
        list.add(text: "Milk")
        let doneID = list.add(text: "Backup")
        list.toggle(id: doneID)
        list.refresh(now: now, calendar: calendar)

        XCTAssertEqual(list.groups.overdue.map(\.text), ["Invoice"])
        XCTAssertEqual(list.groups.today.map(\.text), ["Dentist"])
        XCTAssertEqual(list.groups.upcoming.map(\.text), ["Inspection"])
        XCTAssertEqual(list.groups.noDate.map(\.text), ["Milk"])
        XCTAssertEqual(list.groups.done.map(\.text), ["Backup"])
        XCTAssertEqual(list.groups.openCount, 4)
    }

    func testASpokenTaskKeepsItsWordsAndCanBecomeANoteAgain() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        let library = Library(backend: CoreBackend(store: store))
        let spoken = "Reminder, call the bank Friday at three"

        guard case .task(let body, let due, let allDay) =
                SpokenIntent.parse(spoken, now: now, calendar: calendar) else {
            return XCTFail("a spoken reminder should be a task")
        }
        XCTAssertEqual(due, at(20, 15))
        let id = list.add(text: body, dueAt: due, allDay: allDay, spokenText: spoken, trigger: .manual, duration: 3)
        library.reload()
        XCTAssertTrue(library.notes.isEmpty, "a task is not in the notes list")
        XCTAssertEqual(store.notes.first?.origin, .phone)

        list.makePlainNote(id: id, text: spoken)
        library.reload()
        list.refresh(now: now, calendar: calendar)
        XCTAssertTrue(list.groups.isEmpty)
        XCTAssertEqual(library.notes.map(\.transcript), [spoken])
        XCTAssertNil(store.notes.first?.dueAt)
    }

    func testCompleteIsSafeToRepeat() {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        let id = list.add(text: "Once")
        list.complete(id: id)
        list.complete(id: id)
        XCTAssertEqual(store.notes.first?.done, true)
    }

    func testChangesAreHandedOnForAlerts() async {
        let store = TranscriptStore(path: ":memory:")
        let list = TaskList(store: store)
        var seen: [[String]] = []
        list.onChange = { seen.append($0.map(\.text)) }
        list.add(text: "Ring", dueAt: at(25, 9))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(seen.last, ["Ring"])
    }

    // MARK: Alerts

    func testOnlyOpenTasksWithATimeAheadGetAnAlert() {
        var past = Note(text: "Past"); past.isTask = true; past.dueAt = at(18, 17)
        var soon = Note(text: "Soon"); soon.isTask = true; soon.dueAt = at(19, 11)
        var later = Note(text: "Later"); later.isTask = true; later.dueAt = at(21, 9)
        var done = Note(text: "Done"); done.isTask = true; done.dueAt = at(20, 9); done.done = true
        var undated = Note(text: "Undated"); undated.isTask = true
        var plain = Note(text: "A note"); plain.dueAt = at(20, 9)

        let alerts = ReminderPlan.alerts(for: [later, past, done, undated, plain, soon], now: now)
        XCTAssertEqual(alerts.map(\.body), ["Soon", "Later"])
        XCTAssertEqual(alerts.first?.id, soon.id)
        XCTAssertEqual(alerts.first?.fireAt, at(19, 11))
    }

    func testAlertsStayUnderThePhoneLimit() {
        let notes: [Note] = (0..<100).map { i in
            var n = Note(text: "Task \(i)"); n.isTask = true
            n.dueAt = now.addingTimeInterval(Double(100 - i) * 3600)
            return n
        }
        let alerts = ReminderPlan.alerts(for: notes, now: now)
        XCTAssertEqual(alerts.count, ReminderPlan.limit)
        XCTAssertEqual(alerts.first?.body, "Task 99", "the soonest are kept")
    }

    func testOnlyWhatChangedIsSetAgain() {
        let a = ReminderPlan.Alert(id: UUID(), fireAt: at(20, 9), body: "A")
        let b = ReminderPlan.Alert(id: UUID(), fireAt: at(21, 9), body: "B")
        let gone = ReminderPlan.Alert(id: UUID(), fireAt: at(22, 9), body: "Gone")
        let bMoved = ReminderPlan.Alert(id: b.id, fireAt: at(21, 10), body: "B")

        let changes = ReminderPlan.changes(wanted: [a, bMoved], pending: [a.id: a, b.id: b, gone.id: gone])
        XCTAssertEqual(changes.add, [bMoved], "a snoozed task is replaced, an untouched one is left")
        XCTAssertEqual(changes.remove, [gone.id])
    }

    // MARK: Words for a due time

    func testDueLabels() {
        XCTAssertEqual(DueLabel.text(for: at(19, 15), allDay: false, now: now, calendar: calendar), "Today 15:00")
        XCTAssertEqual(DueLabel.text(for: at(20, 9), allDay: true, now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(DueLabel.text(for: at(18, 17), allDay: false, now: now, calendar: calendar), "Yesterday 17:00")
        XCTAssertEqual(DueLabel.text(for: at(23, 10), allDay: false, now: now, calendar: calendar), "Mon 10:00")
        XCTAssertEqual(DueLabel.text(for: at(30, 9), allDay: true, now: now, calendar: calendar), "30 Nov")
    }
}
