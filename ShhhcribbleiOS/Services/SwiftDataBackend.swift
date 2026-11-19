import Foundation
import SwiftData

/// The SwiftData store behind `Library`. This is the only file, with
/// `Models/Note.swift`, that knows SwiftData exists. Both are retired when
/// the shared package's store arrives.
@MainActor
final class SwiftDataBackend: LibraryBackend {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() {
        do {
            // Keep this store in the app's own sandbox. With the App Group
            // entitlement present SwiftData would otherwise move it into the
            // shared container, which belongs to the shared package's store.
            let config = ModelConfiguration(groupContainer: .none)
            self.container = try ModelContainer(for: Note.self, configurations: config)
        } catch {
            fatalError("Unable to create ModelContainer for Note: \(error)")
        }
    }

    func all() -> [LibraryNote] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.asLibraryNote)
    }

    func insert(_ note: LibraryNote) -> Bool {
        guard fetch(note.id) == nil else { return false }
        let model = Note(
            transcript: note.transcript,
            title: note.title,
            duration: note.duration,
            trigger: note.trigger,
            createdAt: note.createdAt
        )
        model.id = note.id
        model.tags = note.tags
        context.insert(model)
        try? context.save()
        return true
    }

    func update(_ note: LibraryNote) {
        guard let model = fetch(note.id) else { return }
        model.title = note.title
        model.transcript = note.transcript
        model.tags = note.tags
        try? context.save()
    }

    func delete(id: UUID) {
        guard let model = fetch(id) else { return }
        context.delete(model)
        try? context.save()
    }

    func deleteAll() {
        try? context.delete(model: Note.self)
        try? context.save()
    }

    private func fetch(_ id: UUID) -> Note? {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}

private extension Note {
    var asLibraryNote: LibraryNote {
        LibraryNote(
            id: id,
            title: title,
            transcript: transcript,
            createdAt: createdAt,
            duration: duration,
            trigger: trigger,
            tags: tags
        )
    }
}
