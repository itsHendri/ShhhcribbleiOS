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
}
