import Foundation

/// A note as the rest of the app sees it: a plain value, no storage types.
/// Views and services use this and `Library`; only a `LibraryBackend` knows
/// how notes are stored. That keeps the move to the shared package (see
/// docs/ECOSYSTEM.md in the brand folder) to one new backend.
struct LibraryNote: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var transcript: String
    var createdAt: Date
    var duration: TimeInterval
    var trigger: TriggerSource
    var tags: [String]

    init(
        id: UUID = UUID(),
        title: String,
        transcript: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        trigger: TriggerSource,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.createdAt = createdAt
        self.duration = duration
        self.trigger = trigger
        self.tags = tags
    }
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
}

/// The app's notes, newest first. The single place views and services read
/// and write notes.
@MainActor
final class Library: ObservableObject {
    static let shared = Library(backend: SwiftDataBackend())

    @Published private(set) var notes: [LibraryNote]
    private let backend: LibraryBackend

    init(backend: LibraryBackend) {
        self.backend = backend
        self.notes = backend.all().sorted { $0.createdAt > $1.createdAt }
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
        createdAt: Date = Date()
    ) -> Bool {
        let note = LibraryNote(
            id: id,
            title: transcript.autoTitle(),
            transcript: transcript,
            createdAt: createdAt,
            duration: duration,
            trigger: trigger
        )
        guard backend.insert(note) else { return false }
        notes.append(note)
        notes.sort { $0.createdAt > $1.createdAt }
        return true
    }

    /// Appends text to an existing note after a blank line. The title and
    /// tags stay as they are. Does nothing if the note is gone.
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
