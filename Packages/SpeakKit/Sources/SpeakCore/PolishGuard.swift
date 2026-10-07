import Foundation

/// Cheap rules around the LLM: when to skip it, and when to distrust its output.
public enum PolishGuard {
    /// Short, clean phrases go straight through — the transcriber already punctuates them.
    public static func shouldSkip(_ raw: String) -> Bool {
        let words = tokens(raw)
        guard words.count <= 4 else { return false }
        return !containsFillerOrCorrection(raw)
    }

    public static func containsFillerOrCorrection(_ text: String) -> Bool {
        let words = tokens(text)
        if words.contains(where: fillerWords.contains) { return true }
        let joined = " " + words.joined(separator: " ") + " "
        if correctionPhrases.contains(where: { joined.contains(" \($0) ") }) { return true }
        // Stutters / repeated words ("the the").
        return zip(words, words.dropFirst()).contains { $0 == $1 }
    }

    public enum Rejection: Equatable, Sendable {
        case empty
        case preamble
        case tooLong
        case tooShort
        case tooManyNewWords
    }

    /// Returns why `polished` should not be trusted, or nil if it looks like a faithful cleanup of `raw`.
    public static func rejection(raw: String, polished: String) -> Rejection? {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }

        let lower = trimmed.lowercased()
        let rawLower = raw.lowercased()
        if let prefix = preambles.first(where: lower.hasPrefix), !rawLower.hasPrefix(prefix) {
            return .preamble
        }

        let rawCount = raw.count
        if trimmed.count > rawCount * 3 / 2 + 20 { return .tooLong }
        // Self-corrections remove words, but rarely three quarters of them.
        if rawCount >= 40, trimmed.count < rawCount / 4 { return .tooShort }

        let rawWords = Set(tokens(raw))
        let outWords = tokens(trimmed)
        if outWords.count >= 6 {
            let novel = outWords.filter { !rawWords.contains($0) && !isNumeric($0) }.count
            if Double(novel) / Double(outWords.count) > 0.35 { return .tooManyNewWords }
        }
        return nil
    }

    /// Lowercased words with punctuation stripped (keeps apostrophes inside words).
    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { !$0.isEmpty }
    }

    private static func isNumeric(_ word: String) -> Bool {
        word.contains(where: \.isNumber)
    }

    private static let fillerWords: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm"]

    private static let correctionPhrases = [
        "no wait", "wait no", "actually", "scratch that", "i mean", "sorry i meant", "or rather", "let me rephrase",
        "you know", "new line", "new paragraph", "bullet point",
    ]

    private static let preambles = [
        "here is", "here's", "sure", "certainly", "of course", "i'm sorry", "i cannot", "i can't", "as an ai",
        "cleaned", "the cleaned",
    ]
}
