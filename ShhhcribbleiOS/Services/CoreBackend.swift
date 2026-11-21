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
        #if DEBUG
        NoteDetailsRestore.runIfPresent(store: store)
        #endif
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
        watch = store.$notes.dropFirst().merge(with: store.$trashedNotes.dropFirst()).sink { [weak self] _ in
            DispatchQueue.main.async { self?.onExternalChange?() }
        }
    }

    func all() -> [LibraryNote] {
        // The core's shelf: notes, not tasks, and not meetings still waiting
        // for a yes on the Mac.
        store.shelfNotes.map(Self.libraryNote)
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

    /// What the last delete binned, so Undo can take exactly that back out.
    private var lastDeleted: [UUID] = []

    /// A delete moves the note to Recently Deleted (the shared bin, kept 30
    /// days and synced), never removes the row.
    func delete(id: UUID) {
        lastDeleted = store.notes.contains { $0.id == id } ? [id] : []
        store.trashNote(id: id)
    }

    func undoLastDelete() -> Int {
        let ids = lastDeleted.filter { id in store.trashedNotes.contains { $0.id == id } }
        for id in ids { store.restoreNote(id: id) }
        lastDeleted = []
        return ids.count
    }

    func trashed() -> [LibraryNote] {
        store.trashedNotes.filter { !$0.isTask }.map(Self.libraryNote)
    }

    func restore(id: UUID) {
        store.restoreNote(id: id)
    }

    /// For good. Only rows in the bin, so a live note can never go this way.
    func deleteForever(ids: [UUID]) {
        let binned = Set(store.trashedNotes.map(\.id))
        for id in ids where binned.contains(id) { store.deleteNote(id: id) }
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
        delete(ids: store.notes.filter { !$0.isTask }.map(\.id))
    }

    func delete(ids: [UUID]) {
        let live = Set(store.notes.map(\.id))
        lastDeleted = ids.filter { live.contains($0) }
        for id in lastDeleted { store.trashNote(id: id) }
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
        note.deletedAt = row.deletedAt
        return note
    }
}

#if DEBUG
/// One-off repair, debug builds only: puts back a note's origin, raw words
/// and length from a file copied into the app's Documents folder over the
/// cable (`restore-note-details.json`, a list of {id, origin, originDetail,
/// rawText, durationSec}). Only fills fields that are empty, then renames the
/// file so it never runs twice. Written after sync dropped these fields
/// (2026-11-21, fixed in the core at a2587c6). The values stay out of git.
@MainActor
enum NoteDetailsRestore {
    private struct Entry: Decodable {
        let id: UUID
        let origin: String?
        let originDetail: String?
        let rawText: String?
        let durationSec: Double?
    }

    static func runIfPresent(store: TranscriptStore) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = docs.appendingPathComponent("restore-note-details.json")
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        var restored = 0
        for entry in entries {
            guard var row = store.notes.first(where: { $0.id == entry.id }) else { continue }
            if row.rawText == nil, let raw = entry.rawText { row.rawText = raw }
            if row.durationSec == nil, let d = entry.durationSec { row.durationSec = d }
            if row.origin == .typed, let o = entry.origin.flatMap(NoteOrigin.init(rawValue:)) { row.origin = o }
            if row.originDetail == nil, let detail = entry.originDetail { row.originDetail = detail }
            store.updateNote(row, modifiedAt: row.modifiedAt)
            restored += 1
        }
        try? fm.moveItem(at: file, to: docs.appendingPathComponent("restore-note-details.done.json"))
        UserDefaults.standard.set(restored, forKey: "debugNoteDetailsRestored")
    }
}
#endif
