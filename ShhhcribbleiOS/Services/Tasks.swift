import Combine
import Foundation
import ShhhcribbleCore
import WidgetKit

/// A task as the views see it. A task is a note in the shared library with
/// `isTask` set; this is the plain value the screens work with.
struct TaskItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String
    var done: Bool
    var dueAt: Date?
    /// Due on a day with no time. `dueAt` is then 09:00 that day.
    var dueAllDay: Bool
    var completedAt: Date?
    /// The words as they were spoken, when the task came from a recording.
    var spokenText: String?
}

/// The task list's sections, in the order the screen shows them.
struct TaskGroups: Equatable {
    var overdue: [TaskItem] = []
    var today: [TaskItem] = []
    var upcoming: [TaskItem] = []
    var noDate: [TaskItem] = []
    var done: [TaskItem] = []

    var openCount: Int { overdue.count + today.count + upcoming.count + noDate.count }
    var isEmpty: Bool { openCount == 0 && done.isEmpty }
}

/// The app's tasks. The single place views and services read and write
/// them, as `Library` is for notes. Sorting and the rule for "overdue" come
/// from the shared core, so the phone and the Mac agree.
@MainActor
final class TaskList: ObservableObject {
    static let shared: TaskList = {
        let list = TaskList(store: SharedLibrary.store)
        list.onChange = { notes in
            ReminderScheduler.shared.reconcile(with: notes)
            // The home-screen widgets read the same library.
            WidgetCenter.shared.reloadAllTimelines()
        }
        list.onChange?(SharedLibrary.store.notes)
        return list
    }()

    @Published private(set) var groups = TaskGroups()

    /// Called after every change to the stored notes, with all of them.
    /// Alerts (and later the widget) are brought in step from here.
    var onChange: (([Note]) -> Void)?

    private let store: TranscriptStore
    private var watch: AnyCancellable?

    init(store: TranscriptStore) {
        self.store = store
        refresh()
        // `$notes` fires before the array changes, so read on the next turn.
        watch = store.$notes.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                self.onChange?(self.store.notes)
            }
        }
    }

    /// Sorts the tasks again. Also called when the clock matters: a task
    /// due "today" becomes overdue at midnight with no change to the store.
    func refresh(now: Date = Date(), calendar: Calendar = .current) {
        let sections = TaskSections.sections(of: store.notes, now: now, calendar: calendar)
        let fresh = TaskGroups(
            overdue: sections.overdue.map(Self.item),
            today: sections.today.map(Self.item),
            upcoming: sections.upcoming.map(Self.item),
            noDate: sections.noDate.map(Self.item),
            done: sections.done.map(Self.item)
        )
        if fresh != groups { groups = fresh }
    }

    func task(id: UUID) -> TaskItem? {
        store.notes.first { $0.id == id && $0.isTask }.map(Self.item)
    }

    // MARK: Writes

    /// Adds a task. `spokenText`, `trigger` and `duration` are set when it
    /// came from a recording.
    @discardableResult
    func add(
        text: String,
        dueAt: Date? = nil,
        allDay: Bool = false,
        spokenText: String? = nil,
        trigger: TriggerSource? = nil,
        duration: TimeInterval? = nil
    ) -> UUID {
        var note = Note(text: text)
        note.isTask = true
        note.dueAt = dueAt
        note.dueAllDay = dueAt != nil && allDay
        note.origin = .phone
        note.originDetail = trigger?.rawValue
        note.rawText = spokenText
        note.durationSec = duration
        store.addNote(note)
        return note.id
    }

    func toggle(id: UUID) {
        store.toggleNoteDone(id: id)
    }

    /// Marks a task done. Does nothing if it already is: an alert's Done
    /// button can arrive after the task was ticked elsewhere.
    func complete(id: UUID) {
        guard let task = task(id: id), !task.done else { return }
        store.toggleNoteDone(id: id)
    }

    func setDue(id: UUID, dueAt: Date?, allDay: Bool) {
        store.setNoteDue(id: id, dueAt: dueAt, allDay: allDay)
    }

    func rename(id: UUID, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var note = store.notes.first(where: { $0.id == id }), note.text != text else { return }
        note.text = text
        note.richText = nil
        store.updateNote(note)
    }

    func snooze(id: UUID, until date: Date = ReminderPlanner.snoozeDate()) {
        store.snoozeNote(id: id, until: date)
    }

    /// To Recently Deleted, like a note. Its alert goes, since the bin is
    /// not in `store.notes`.
    func delete(id: UUID) {
        store.trashNote(id: id)
    }

    /// Turns a task back into an ordinary note. With `text`, the note gets
    /// that text (the undo of a spoken "Reminder": the words as they were
    /// before the keyword was taken off).
    func makePlainNote(id: UUID, text: String? = nil) {
        store.setNoteIsTask(id: id, isTask: false)
        guard let text, var note = store.notes.first(where: { $0.id == id }), note.text != text else { return }
        note.text = text
        note.richText = nil
        store.updateNote(note)
    }

    private static func item(_ note: Note) -> TaskItem {
        TaskItem(
            id: note.id,
            text: note.text,
            done: note.done,
            dueAt: note.dueAt,
            dueAllDay: note.dueAllDay,
            completedAt: note.completedAt,
            spokenText: note.rawText
        )
    }
}
