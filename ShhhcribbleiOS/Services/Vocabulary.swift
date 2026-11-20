import Combine
import Foundation
import ShhhcribbleCore

/// The shared dictionary (find and replace, custom words), readable from any
/// thread.
///
/// The store is main-actor only, and transcription runs off it. So this keeps
/// a copy that follows the store, and `TranscriptionService` applies that.
final class Vocabulary: @unchecked Sendable {
    static let shared = Vocabulary()

    private let lock = NSLock()
    private var entries: [DictionaryEntry] = []
    private var watch: AnyCancellable?

    @MainActor
    func follow(_ store: TranscriptStore) {
        set(store.dictionaryEntries)
        watch = store.$dictionaryEntries.sink { [weak self] in self?.set($0) }
    }

    func set(_ new: [DictionaryEntry]) {
        lock.lock(); defer { lock.unlock() }
        entries = new
    }

    /// Whole-word replacement, in the dictionary's order. The same rule the
    /// Mac applies.
    func apply(to text: String) -> String {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return PersonalDictionary.apply(snapshot, to: text)
    }
}

/// What the two vocabulary screens edit. A custom word is a dictionary entry
/// whose replacement is the phrase itself with the casing fixed ("github"
/// heard, "GitHub" written); anything else is a substitution. Both are the
/// same thing in the shared library, so both sync and both work on the Mac.
@MainActor
enum VocabularyEdit {
    struct Rule: Identifiable, Equatable {
        let id: UUID
        var find: String
        var replace: String
    }

    private static var store: TranscriptStore { SharedLibrary.store }

    private static func isCustomWord(_ entry: DictionaryEntry) -> Bool {
        entry.phrase.caseInsensitiveCompare(entry.replacement) == .orderedSame
    }

    static func customWords() -> [Rule] {
        store.dictionaryEntries.filter(isCustomWord).map(rule).sorted(by: byFind)
    }

    static func substitutions() -> [Rule] {
        store.dictionaryEntries.filter { !isCustomWord($0) }.map(rule).sorted(by: byFind)
    }

    /// Adds an entry, replacing any with the same phrase.
    static func add(find: String, replace: String) {
        for entry in store.dictionaryEntries
        where entry.phrase.caseInsensitiveCompare(find) == .orderedSame {
            store.deleteDictionaryEntry(id: entry.id)
        }
        store.addDictionaryEntry(DictionaryEntry(phrase: find, replacement: replace))
    }

    static func delete(id: UUID) {
        store.deleteDictionaryEntry(id: id)
    }

    private static func rule(_ entry: DictionaryEntry) -> Rule {
        Rule(id: entry.id, find: entry.phrase, replace: entry.replacement)
    }

    private static func byFind(_ a: Rule, _ b: Rule) -> Bool {
        a.find.localizedCaseInsensitiveCompare(b.find) == .orderedAscending
    }
}

/// Moves the custom words and substitutions this phone kept in UserDefaults
/// into the shared dictionary, once. Custom filler words stay local.
@MainActor
enum VocabularyMigration {
    private static let flag = "didMoveVocabularyToLibrary"

    static func runIfNeeded(into store: TranscriptStore, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flag) else { return }
        var known = Set(store.dictionaryEntries.map { $0.phrase.lowercased() })

        var incoming: [(String, String)] = []
        if let data = defaults.data(forKey: "substitutionRules"),
           let rules = try? JSONDecoder().decode([String: String].self, from: data) {
            incoming += rules.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        let words = (defaults.array(forKey: "customHotwords") as? [String]) ?? []
        incoming += words.map { ($0, $0) }

        for (find, replace) in incoming where !find.isEmpty && !known.contains(find.lowercased()) {
            store.addDictionaryEntry(DictionaryEntry(phrase: find, replacement: replace))
            known.insert(find.lowercased())
        }
        defaults.set(true, forKey: flag)
    }
}
