import Foundation
import SwiftData

@MainActor
@Observable
final class NoteDetailViewModel {
    let note: Note

    init(note: Note) {
        self.note = note
    }

    var formattedTimestamp: String {
        note.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDuration: String {
        let seconds = Int(note.duration.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    func delete(in context: ModelContext) {
        context.delete(note)
        try? context.save()
    }

    func save(in context: ModelContext) {
        try? context.save()
    }
}
