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

        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "^[,;]+\\s*", with: "", options: .regularExpression)

        return s
    }
}
