import Foundation
import SwiftData

@MainActor
final class NotesRepository {
    static let shared = NotesRepository()

    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    private init() {
        do {
            self.container = try ModelContainer(for: Note.self)
        } catch {
            fatalError("Unable to create ModelContainer for Note: \(error)")
        }
    }

    func insert(transcript: String, duration: TimeInterval, trigger: TriggerSource) {
        let title = transcript.autoTitle()
        let note = Note(
            transcript: transcript,
            title: title,
            duration: duration,
            trigger: trigger
        )
        context.insert(note)
        try? context.save()
    }

    /// Append `newText` to the existing note identified by `id`, separated by
    /// `\n\n`. Title and tags are left untouched. No-op if the note isn't
    /// found (e.g. it was deleted between the append start and the commit).
    func append(transcript newText: String, to id: UUID) {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        guard let note = try? context.fetch(descriptor).first else { return }
        note.transcript = note.transcript.isEmpty
            ? newText
            : note.transcript + "\n\n" + newText
        try? context.save()
    }

    /// Look up a note's title by id without exposing the model context.
    func title(for id: UUID) -> String? {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor).first)?.title
    }
}
