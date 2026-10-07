import Foundation
import NaturalLanguage

/// Adjusts dictated text to fit the text around the cursor: spacing, capitalization of the first word,
/// and trailing punctuation when inserting into the middle of a sentence.
public enum InsertionFormatter {
    /// - Parameters:
    ///   - before: A few characters just before the cursor; nil if unknown, empty at the start of a field.
    ///   - after: The character just after the cursor (or selection); nil if unknown or at the end.
    ///   - keepCapitalized: Words that must keep their capitalization (the user's dictionary).
    public static func format(
        _ text: String, before: String?, after: Character?, keepCapitalized: [String] = []
    ) -> String {
        var text = text
        guard let first = text.first else { return text }

        // Only when the cursor is on the same line as the previous word (not after a line break or indent).
        if let before, let previous = before.last(where: { !$0.isWhitespace }),
           !before.reversed().prefix(while: \.isWhitespace).contains(where: \.isNewline),
           continuesSentence(previous) {
            text = lowercasingFirstWord(text, keepCapitalized: keepCapitalized)
        }

        if let after, after.isLetter || after.isNumber, text.last.map({ !$0.isWhitespace }) ?? false {
            // Inserting in front of more words: the sentence carries on, so no full stop, and keep a gap.
            if text.hasSuffix("."), !text.hasSuffix("..") { text.removeLast() }
            text += " "
        }

        if let previous = before?.last, needsLeadingSpace(after: previous, first: first) {
            text = " " + text
        }
        return text
    }

    /// After a word or a comma the sentence is still going, so the next word shouldn't be capitalized.
    static func continuesSentence(_ previous: Character) -> Bool {
        // Not "-": at the start of a line that's a bullet, and the item should stay capitalized.
        previous.isLetter || previous.isNumber || ",;:–—(".contains(previous)
    }

    static func needsLeadingSpace(after previous: Character, first: Character) -> Bool {
        if previous.isWhitespace || "([{\"'“‘/-".contains(previous) { return false }
        if first.isWhitespace || ".,;:!?)]}".contains(first) { return false }
        return true
    }

    static func lowercasingFirstWord(_ text: String, keepCapitalized: [String]) -> String {
        guard let wordRange = text.range(of: #"^\p{L}[\p{L}'’]*"#, options: .regularExpression) else { return text }
        let word = String(text[wordRange])
        guard shouldLowercase(word, in: text, keepCapitalized: keepCapitalized) else { return text }
        return word.prefix(1).lowercased() + word.dropFirst() + text[wordRange.upperBound...]
    }

    static func shouldLowercase(_ word: String, in text: String, keepCapitalized: [String]) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        // "I", "I'm", acronyms (API) and mixed case (iPhone, McDonald) stay as they are.
        let stem = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? word
        if stem == "I" { return false }
        if word.dropFirst().contains(where: \.isUppercase) { return false }
        if keepCapitalized.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { return false }
        if calendarWords.contains(word.lowercased()) { return false }
        return !isName(at: text.startIndex, in: text)
    }

    /// Days and months are capitalized in English but aren't tagged as names.
    private static let calendarWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "june", "july", "august", "september", "october",
        "november", "december",
    ]

    private static func isName(at index: String.Index, in text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let (tag, _) = tagger.tag(at: index, unit: .word, scheme: .nameType)
        return tag == .personalName || tag == .placeName || tag == .organizationName
    }
}
