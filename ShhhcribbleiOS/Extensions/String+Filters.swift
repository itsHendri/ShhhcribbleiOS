import Foundation

enum FillerWordFilter {

    static func filter(_ text: String) -> String {
        var s = text

        let definite = [
            "\\b[Uu]m+h?\\b,?",
            "\\b[Uu]h+\\b,?",
            "\\b[Hh]m+\\b,?",
            "\\b[Ee]r+\\b,?",
            "\\b[Ee]rm+\\b,?",
        ]
        for pattern in definite {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        s = s.replacingOccurrences(of: ",\\s*[Yy]ou know,\\s*",
                                   with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: ",?\\s*[Yy]ou know\\.?$",
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[Yy]ou know,\\s*",
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[Ll]ike,\\s+",
                                   with: "", options: .regularExpression)

        // User-supplied filler words (whole-word, case-insensitive, optional
        // trailing comma). Applied alongside the built-in list so users can
        // strip personal tics like "basically", "literally", "honestly".
        let custom = (UserDefaults.standard.array(forKey: "customFillerWords") as? [String]) ?? []
        for raw in custom {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let pattern = "\\b\(escaped)\\b,?"
            s = s.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "^[,;]+\\s*", with: "", options: .regularExpression)

        return s
    }
}
