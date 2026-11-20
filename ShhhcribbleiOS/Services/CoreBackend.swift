import Combine
import Foundation
import ShhhcribbleCore

/// Where the shared library lives on the phone, and the one store the app
/// opens on it.
///
/// The database sits in the App Group container so the widget (and later the
/// keyboard) can open the same file through `LibraryReader`. SQLite keeps
/// three files side by side while it is open; they share this folder.
@MainActor
enum SharedLibrary {
    /// The app's store. Opening it creates the file and brings its schema up
    /// to date; only the app does that, never an extension.
    static let store: TranscriptStore = {
        let store = TranscriptStore.makeDefault(at: databaseURL(), runLegacyMacMigrations: false)
        store.observeOtherProcesses()
        VocabularyMigration.runIfNeeded(into: store)
        Vocabulary.shared.follow(store)
        return store
    }()

    nonisolated static func databaseURL() -> URL { LibraryLocation.databaseURL() }
}

/// Notes kept in the shared library (`ShhhcribbleCore`), the same store the
/// Mac app uses. The only file besides `Vocabulary.swift` that knows the
/// core's types; everything else goes through `Library`.
///
/// The phone's notes screen shows every note that is not a task. Tasks get
/// their own screen.
@MainActor
final class CoreBackend: LibraryBackend {
    private let store: TranscriptStore
    private var watch: AnyCancellable?

    var onExternalChange: (() -> Void)?

    init(store: TranscriptStore) {
        self.store = store
        // `$notes` fires before the array changes, so read on the next turn.
        watch = store.$notes.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.onExternalChange?() }
        }
    }

    func all() -> [LibraryNote] {
        store.notes.filter { !$0.isTask }.map(Self.libraryNote)
    }

    func insert(_ note: LibraryNote) -> Bool {
        var row = Note(id: note.id, createdAt: note.createdAt, modifiedAt: note.createdAt, text: note.transcript)
        row.tags = note.tags
        row.origin = .phone
        row.originDetail = note.trigger.rawValue
        row.rawText = note.rawTranscript
        row.durationSec = note.duration
        return store.addNoteIfAbsent(row)
    }

    func update(_ note: LibraryNote) {
        guard var row = store.notes.first(where: { $0.id == note.id }) else { return }
        guard row.text != note.transcript || row.tags != note.tags else { return }
        if row.text != note.transcript {
            row.text = note.transcript
            // Plain text is the truth. The Mac's styling no longer matches
            // it, so it goes (agreed with the Mac track).
            row.richText = nil
        }
        row.tags = note.tags
        store.updateNote(row)
    }

    /// The full rows the last delete removed, kept in memory only, so Undo
    /// puts back every field (the Mac's styling, summary, times), not just
    /// what the phone shows. Gone when the app quits; the 30-day bin comes
    /// with the shared library's "deleted at" field.
    private var lastDeleted: [Note] = []

    func delete(id: UUID) {
        lastDeleted = store.notes.filter { $0.id == id }
        store.deleteNote(id: id)
    }

    func undoLastDelete() -> Int {
        var count = 0
        for row in lastDeleted where store.addNoteIfAbsent(row) { count += 1 }
        lastDeleted = []
        return count
    }

    func saveSummary(id: UUID, summary: String, items: [NoteActionItem], at date: Date) {
        store.updateNoteSummary(
            id: id,
            summary: summary,
            actionItems: items.map {
                ActionItem(text: $0.text, owner: ActionItemOwner(rawValue: $0.owner) ?? .unassigned, quote: $0.quote)
            },
            generatedAt: date
        )
    }

    func deleteAll() {
        lastDeleted = store.notes.filter { !$0.isTask }
        for note in store.notes where !note.isTask {
            store.deleteNote(id: note.id)
        }
    }

    private static func libraryNote(_ row: Note) -> LibraryNote {
        var note = LibraryNote(
            id: row.id,
            transcript: row.text,
            rawTranscript: row.rawText,
            createdAt: row.createdAt,
            duration: row.durationSec ?? 0,
            trigger: row.originDetail.flatMap(TriggerSource.init(rawValue:)) ?? .manual,
            tags: row.tags
        )
        note.summary = row.summary
        note.actionItems = row.actionItems.map {
            NoteActionItem(text: $0.text, quote: $0.quote, owner: $0.owner.rawValue)
        }
        note.summaryGeneratedAt = row.summaryGeneratedAt
        return note
    }
}
