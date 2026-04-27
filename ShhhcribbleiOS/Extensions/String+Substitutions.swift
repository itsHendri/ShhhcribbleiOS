import Foundation

enum SubstitutionPass {

    static func apply(_ text: String, rules: [String: String]) -> String {
        guard !rules.isEmpty, !text.isEmpty else { return text }
        var s = text
        for (find, replace) in rules where !find.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: find)
            let pattern = "\\b\(escaped)\\b"
            s = s.replacingOccurrences(
                of: pattern,
                with: replace,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return s
    }

    /// Reads `substitutionRules` (Data, JSON-encoded [String: String]) and
    /// `customHotwords` (synthesised as lowercased→original case-insensitive
    /// rewrites) from UserDefaults, then returns the merged dict. Explicit
    /// substitution rules win on key collisions.
    static func currentRules() -> [String: String] {
        var merged: [String: String] = [:]

        let hotwords = (UserDefaults.standard.array(forKey: "customHotwords") as? [String]) ?? []
        for word in hotwords where !word.isEmpty {
            merged[word.lowercased()] = word
        }

        if let data = UserDefaults.standard.data(forKey: "substitutionRules"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in decoded where !k.isEmpty {
                merged[k] = v
            }
        }
        return merged
    }
}
