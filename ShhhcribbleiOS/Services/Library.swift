import Foundation

/// A note as the rest of the app sees it: a plain value, no storage types.
/// Views and services use this and `Library`; only a `LibraryBackend` knows
/// how notes are stored (`CoreBackend`, on the library shared with the Mac).
struct LibraryNote: Identifiable, Hashable, Sendable {
    let id: UUID
    var transcript: String
    /// What was heard, before the dictionary and any cleanup. Nil for notes
    /// that were not spoken on this phone.
    var rawTranscript: String?
    var createdAt: Date
    var duration: TimeInterval
    var trigger: TriggerSource
    var tags: [String]
    /// Made on request by the on-device model. Nil until then.
    var summary: String?
    var actionItems: [NoteActionItem] = []
    var summaryGeneratedAt: Date?
    /// Set while the note is in Recently Deleted.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        transcript: String,
        rawTranscript: String? = nil,
        createdAt: Date = Date(),
        duration: TimeInterval,
        trigger: TriggerSource,
        tags: [String] = []
    ) {
        self.id = id
        self.transcript = transcript
        self.rawTranscript = rawTranscript
        self.createdAt = createdAt
        self.duration = duration
        self.trigger = trigger
        self.tags = tags
    }

    /// Taken from the first sentence, as on the Mac. Notes are shared, so
    /// the phone has no title of its own to edit.
    var title: String { transcript.autoTitle() }
}

/// Something a summary found to do, with the sentence it came from.
struct NoteActionItem: Hashable, Sendable {
    var text: String
    /// The words in the note this item was taken from.
    var quote: String
    /// Who said they would do it, as the shared library spells it.
    var owner: String
}

/// How a note came to exist.
enum TriggerSource: String, Codable, Sendable {
    case controlCenter
    case airPods
    case backTap
    case actionButton
    case keyboard
    case manual
    /// Siri, the Shortcuts app, Back Tap, the Action Button or the URL
    /// scheme. They all arrive through the same intent, so the app cannot
    /// tell them apart.
    case shortcut
    /// Transcribed from an audio file, not the microphone.
    case file
    /// Started from the record button on the home-screen widget.
    case widget
}

/// Storage behind the library. Implementations are free to be slow on
/// `all()`; `Library` calls it once and then keeps its own copy in step.
@MainActor
protocol LibraryBackend {
    func all() -> [LibraryNote]
    /// Returns false, and stores nothing, when a note with that id exists.
    func insert(_ note: LibraryNote) -> Bool
    func update(_ note: LibraryNote)
    /// Moves the note to Recently Deleted.
    func delete(id: UUID)
    /// Moves every note (not tasks) to Recently Deleted.
    func deleteAll()
    /// Moves these notes to Recently Deleted as one step, so one Undo
    /// brings them all back.
    func delete(ids: [UUID])
    /// Takes back what the last `delete` or `deleteAll` binned. Returns how
    /// many notes came back. A later delete replaces what can be undone.
    func undoLastDelete() -> Int
    /// Recently Deleted, most recently binned first.
    func trashed() -> [LibraryNote]
    func restore(id: UUID)
    /// Deletes for good. Only notes in Recently Deleted.
    func deleteForever(ids: [UUID])
    /// Stores a summary. Not an edit: the note keeps its modified time.
    func saveSummary(id: UUID, summary: String, items: [NoteActionItem], at date: Date)
    /// Called when the stored notes changed by another hand: the widget, the
    /// Mac through sync, the recorder receiver. `Library` reads again.
    var onExternalChange: (() -> Void)? { get set }
}

/// The app's notes, newest first. The single place views and services read
/// and write notes.
@MainActor
final class Library: ObservableObject {
    static let shared = Library(backend: CoreBackend(store: SharedLibrary.store))

    @Published private(set) var notes: [LibraryNote]
    /// Recently Deleted, most recently binned first.
    @Published private(set) var trashed: [LibraryNote]
    private var backend: LibraryBackend

    /// How long a note stays in Recently Deleted.
    static let binDays = 30

    init(backend: LibraryBackend) {
        self.backend = backend
        self.notes = backend.all().sorted { $0.createdAt > $1.createdAt }
        self.trashed = backend.trashed()
        self.backend.onExternalChange = { [weak self] in self?.reload() }
    }

    /// Reads the notes again from storage. Publishes only when they differ,
    /// so the app's own writes do not redraw twice.
    func reload() {
        let fresh = backend.all().sorted { $0.createdAt > $1.createdAt }
        if fresh != notes { notes = fresh }
        let bin = backend.trashed()
        if bin != trashed { trashed = bin }
    }

    func restore(id: UUID) {
        backend.restore(id: id)
        reload()
    }

    func restoreAll() {
        for note in trashed { backend.restore(id: note.id) }
        reload()
    }

    func deleteForever(ids: [UUID]) {
        backend.deleteForever(ids: ids)
        reload()
    }

    /// Days before a binned note is removed for good, at least 0.
    static func daysLeft(_ note: LibraryNote, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let deleted = note.deletedAt,
              let end = calendar.date(byAdding: .day, value: binDays, to: deleted) else { return binDays }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: end)).day ?? 0
        return max(0, days)
    }

    func note(id: UUID) -> LibraryNote? {
        notes.first { $0.id == id }
    }

    func title(for id: UUID) -> String? {
        note(id: id)?.title
    }

    /// Every tag in use, sorted.
    var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted()
    }

    /// Adds a note. With an explicit `id` this is insert-if-absent: a second
    /// call with the same id changes nothing and returns false. Recorder
    /// notes rely on that, since two receivers may fetch the same recording.
    @discardableResult
    func insert(
        transcript: String,
        duration: TimeInterval,
        trigger: TriggerSource,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawTranscript: String? = nil
    ) -> Bool {
        let note = LibraryNote(
            id: id,
            transcript: transcript,
            rawTranscript: rawTranscript,
            createdAt: createdAt,
            duration: duration,
            trigger: trigger
        )
        guard backend.insert(note) else { return false }
        notes.append(note)
        notes.sort { $0.createdAt > $1.createdAt }
        return true
    }

    /// Appends text to an existing note after a blank line. The tags stay as
    /// they are. Does nothing if the note is gone.
    func append(transcript newText: String, to id: UUID) {
        guard var note = note(id: id) else { return }
        note.transcript = note.transcript.isEmpty
            ? newText
            : note.transcript + "\n\n" + newText
        update(note)
    }

    func update(_ note: LibraryNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        guard notes[index] != note else { return }
        notes[index] = note
        backend.update(note)
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        backend.delete(id: id)
        reload()
    }

    /// Brings back the notes the last delete removed. See
    /// `LibraryBackend.undoLastDelete`.
    @discardableResult
    func undoLastDelete() -> Int {
        let count = backend.undoLastDelete()
        if count > 0 { reload() }
        return count
    }

    func saveSummary(id: UUID, summary: String, items: [NoteActionItem], at date: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].summary = summary
        notes[index].actionItems = items
        notes[index].summaryGeneratedAt = date
        backend.saveSummary(id: id, summary: summary, items: items, at: date)
    }

    func deleteAll() {
        notes.removeAll()
        backend.deleteAll()
        reload()
    }

    func delete(ids: [UUID]) {
        let set = Set(ids)
        notes.removeAll { set.contains($0.id) }
        backend.delete(ids: ids)
        reload()
    }
}

/// Keeps notes in memory only. Used by tests.
@MainActor
final class InMemoryBackend: LibraryBackend {
    private var stored: [UUID: LibraryNote] = [:]
    private var bin: [UUID: LibraryNote] = [:]
    private var lastDeleted: [UUID] = []
    var onExternalChange: (() -> Void)?

    func all() -> [LibraryNote] { Array(stored.values) }

    func insert(_ note: LibraryNote) -> Bool {
        guard stored[note.id] == nil, bin[note.id] == nil else { return false }
        stored[note.id] = note
        return true
    }

    func update(_ note: LibraryNote) { stored[note.id] = note }

    func saveSummary(id: UUID, summary: String, items: [NoteActionItem], at date: Date) {
        stored[id]?.summary = summary
        stored[id]?.actionItems = items
        stored[id]?.summaryGeneratedAt = date
    }

    func delete(id: UUID) {
        lastDeleted = stored[id] == nil ? [] : [id]
        bin(id)
    }

    func deleteAll() {
        lastDeleted = Array(stored.keys)
        for id in lastDeleted { bin(id) }
    }

    func delete(ids: [UUID]) {
        lastDeleted = ids.filter { stored[$0] != nil }
        for id in lastDeleted { bin(id) }
    }

    private func bin(_ id: UUID) {
        guard var note = stored.removeValue(forKey: id) else { return }
        note.deletedAt = Date()
        bin[id] = note
    }

    func undoLastDelete() -> Int {
        let ids = lastDeleted.filter { bin[$0] != nil }
        for id in ids { restore(id: id) }
        lastDeleted = []
        return ids.count
    }

    func trashed() -> [LibraryNote] {
        bin.values.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func restore(id: UUID) {
        guard var note = bin.removeValue(forKey: id) else { return }
        note.deletedAt = nil
        stored[id] = note
    }

    func deleteForever(ids: [UUID]) {
        for id in ids { bin[id] = nil }
    }
}
