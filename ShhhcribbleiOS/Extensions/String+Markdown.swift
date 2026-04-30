import Foundation

extension String {
    /// Heuristic — true if the string contains markdown that's worth rendering.
    /// Drives NoteDetailView's view-vs-edit default. Matches:
    /// - line starting with `# `, `## `, `### `
    /// - line starting with `- `, `* `, or `<digits>. `
    /// - inline link `[text](url)` anywhere
    var containsMarkdownSyntax: Bool {
        guard !isEmpty else { return false }
        let range = NSRange(startIndex..<endIndex, in: self)
        return Self.markdownRegex.firstMatch(in: self, range: range) != nil
    }

    private static let markdownRegex: NSRegularExpression = {
        // (?m) anchors ^ to line starts. Alternatives are mutually exclusive.
        let pattern = #"(?m)(?:^\s*(?:#{1,3} |[-*] |\d+\. ))|\[[^\]]+\]\([^)]+\)"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}
