import Foundation

extension String {
    /// Best-effort one-line title for a transcript: first sentence, or
    /// the leading run of words up to ~60 characters. Trims whitespace
    /// and trailing punctuation. Falls back to "Untitled" for empty input.
    func autoTitle(maxLength: Int = 60) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        let terminators: Set<Character> = [".", "!", "?"]
        var firstSentence = ""
        for ch in trimmed {
            if terminators.contains(ch) { break }
            firstSentence.append(ch)
        }
        firstSentence = firstSentence.trimmingCharacters(in: .whitespaces)

        let candidate = firstSentence.isEmpty ? trimmed : firstSentence
        if candidate.count <= maxLength { return candidate }

        let prefix = candidate.prefix(maxLength)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
