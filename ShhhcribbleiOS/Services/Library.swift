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
}

/// Storage behind the library. Implementations are free to be slow on
/// `all()`; `Library` calls it once and then keeps its own copy in step.
@MainActor
protocol LibraryBackend {
    func all() -> [LibraryNote]
    /// Returns false, and stores nothing, when a note with that id exists.
    func insert(_ note: LibraryNote) -> Bool
    func update(_ note: LibraryNote)
    func delete(id: UUID)
    func deleteAll()
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
    private var backend: LibraryBackend

    init(backend: LibraryBackend) {
        self.backend = backend
        self.notes = backend.all().sorted { $0.createdAt > $1.createdAt }
        self.backend.onExternalChange = { [weak self] in self?.reload() }
    }

    /// Reads the notes again from storage. Publishes only when they differ,
    /// so the app's own writes do not redraw twice.
    func reload() {
        let fresh = backend.all().sorted { $0.createdAt > $1.createdAt }
        if fresh != notes { notes = fresh }
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
    }

    func deleteAll() {
        notes.removeAll()
        backend.deleteAll()
    }
}

/// Keeps notes in memory only. Used by tests.
@MainActor
final class InMemoryBackend: LibraryBackend {
    private var stored: [UUID: LibraryNote] = [:]
    var onExternalChange: (() -> Void)?

    func all() -> [LibraryNote] { Array(stored.values) }

    func insert(_ note: LibraryNote) -> Bool {
        guard stored[note.id] == nil else { return false }
        stored[note.id] = note
        return true
    }

    func update(_ note: LibraryNote) { stored[note.id] = note }
    func delete(id: UUID) { stored[id] = nil }
    func deleteAll() { stored.removeAll() }
}
