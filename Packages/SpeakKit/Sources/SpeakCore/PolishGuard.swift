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
        case droppedContent
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
        // Self-corrections remove words, but rarely three quarters of them (unless a whole clause was retracted).
        let shortest = containsCorrection(raw) ? rawCount / 8 : rawCount / 4
        if rawCount >= 40, trimmed.count < shortest { return .tooShort }

        // The model shouldn't summarize: a self-correction removes a word or two, not whole clauses.
        let outSet = Set(tokens(trimmed))
        let contentWords = tokens(raw).filter {
            $0.count >= 4 && !fillerWords.contains($0) && !correctionWords.contains($0) && !numberWords.contains($0)
        }
        let missing = contentWords.filter { !outSet.contains($0) }.count
        // A spoken correction can legitimately replace a whole clause.
        let allowed = containsCorrection(raw) ? max(6, contentWords.count / 2) : max(3, contentWords.count / 5)
        if missing > allowed { return .droppedContent }

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

    /// Words that only signal a correction; dropping them is expected.
    private static let correctionWords: Set<String> = [
        "actually", "sorry", "meant", "wait", "scratch", "that", "rather", "like", "know", "mean",
    ]

    /// Spelled-out numbers become digits ("twenty five" → 25).
    private static let numberWords: Set<String> = [
        "zero", "four", "five", "nine", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty",
        "ninety", "hundred", "thousand", "million", "billion", "percent", "first", "second", "third", "fourth",
        "fifth",
    ]

    static func containsCorrection(_ text: String) -> Bool {
        let joined = " " + tokens(text).joined(separator: " ") + " "
        return ["no wait", "wait no", "actually", "scratch that", "sorry i meant", "i meant", "or rather", "make that"]
            .contains { joined.contains(" \($0) ") }
    }

    private static let correctionPhrases = [
        "no wait", "wait no", "actually", "scratch that", "i mean", "sorry i meant", "or rather", "let me rephrase",
        "you know",
    ]

    private static let preambles = [
        "here is", "here's", "sure", "certainly", "of course", "i'm sorry", "i cannot", "i can't", "as an ai",
        "cleaned", "the cleaned",
    ]
}
