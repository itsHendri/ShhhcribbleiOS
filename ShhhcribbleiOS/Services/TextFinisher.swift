import Foundation
import ShhhcribbleCore

/// Turns what was heard into what is saved, once, after Stop. Never used on
/// live partials: the on-device model is too slow for that and its output
/// would flicker.
///
/// The order is the Mac's: the shared dictionary on the raw words first, so
/// the model sees corrected names; then on-device cleanup (Apple's model,
/// with the core's guards against added or dropped content); and when that
/// is off, unavailable or rejected, the filler-word filter.
enum TextFinisher {
    static let cleanupKey = "cleanupEnabled"

    /// On by default, as on the Mac.
    static var cleanupEnabled: Bool {
        UserDefaults.standard.object(forKey: cleanupKey) as? Bool ?? true
    }

    /// Whether Apple's on-device model can run right now.
    static var cleanupAvailable: Bool {
        TranscriptCleaner.availability.isAvailable
    }

    struct Finished: Equatable {
        let text: String
        /// True when the on-device model produced the text.
        let cleaned: Bool
    }

    static func finish(_ raw: String) async -> Finished {
        let corrected = Vocabulary.shared.apply(to: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !corrected.isEmpty else { return Finished(text: "", cleaned: false) }

        if cleanupEnabled, cleanupAvailable,
           let cleaned = await TranscriptCleaner.clean(corrected), !cleaned.isEmpty {
            // The model is careful and can leave an "uh" behind. The filter
            // is cheap and only ever removes fillers, so it runs here too.
            return Finished(text: fallback(cleaned), cleaned: true)
        }
        return Finished(text: fallback(corrected), cleaned: false)
    }

    /// The floor every transcript gets when the model did not shape it.
    static func fallback(_ corrected: String) -> String {
        let filterOn = UserDefaults.standard.object(forKey: "filterFillerWords") as? Bool ?? true
        return filterOn ? FillerWordFilter.filter(corrected) : corrected
    }
}

/// Summaries of a note, made on the phone by Apple's on-device model and
/// only when asked for.
@MainActor
final class Summaries: ObservableObject {
    static let shared = Summaries()

    /// Notes being summarised right now.
    @Published private(set) var working: Set<UUID> = []
    /// Notes whose last attempt gave nothing.
    @Published private(set) var failed: Set<UUID> = []

    var available: Bool { TranscriptSummarizer.availability.isAvailable }

    func generate(for id: UUID, in library: Library? = nil) async {
        let library = library ?? Library.shared
        guard !working.contains(id), let note = library.note(id: id) else { return }
        working.insert(id)
        failed.remove(id)
        defer { working.remove(id) }

        let text = note.transcript
        guard let result = await TranscriptSummarizer.summarize(text) else {
            failed.insert(id)
            return
        }
        library.saveSummary(
            id: id,
            summary: result.summary,
            items: result.actionItems.map {
                NoteActionItem(text: $0.text, quote: $0.quote, owner: $0.owner.rawValue)
            }
        )
    }
}
