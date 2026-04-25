import Foundation
import Combine

@MainActor
final class TranscriptionStore: ObservableObject {
    static let shared = TranscriptionStore()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let key = "transcription_history"
    private let maxEntries = 50
    private let defaults = UserDefaults.standard

    private init() {
        entries = load()
    }

    func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = entries
        updated.insert(TranscriptionEntry(text: trimmed), at: 0)
        if updated.count > maxEntries { updated = Array(updated.prefix(maxEntries)) }
        entries = updated
        save(updated)
    }

    func delete(at offsets: IndexSet) {
        var updated = entries
        updated.remove(atOffsets: offsets)
        entries = updated
        save(updated)
    }

    func clearAll() {
        entries = []
        save([])
    }

    private func load() -> [TranscriptionEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TranscriptionEntry].self, from: data)) ?? []
    }

    private func save(_ list: [TranscriptionEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }
}
