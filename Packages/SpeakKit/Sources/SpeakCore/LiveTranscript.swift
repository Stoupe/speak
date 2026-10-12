import Foundation

/// What the pill's card shows while dictating: cleaned-up text, then raw text still waiting to be cleaned up,
/// then the words the recognizer may still change. Concatenated, the three read as one passage.
public struct LiveTranscript: Sendable, Equatable {
    public var polished: String
    /// Finalized transcript that hasn't been polished yet (with a leading space when it follows other text).
    public var pending: String
    /// Text the recognizer may still revise (with a leading space when it follows other text).
    public var volatile: String

    public init(polished: String = "", pending: String = "", volatile: String = "") {
        self.polished = polished
        self.pending = pending
        self.volatile = volatile
    }

    public var isEmpty: Bool { polished.isEmpty && pending.isEmpty && volatile.isEmpty }

    /// - Parameters:
    ///   - polished: Cleaned-up text for the first `polishedThrough` characters of `snapshot.finalized`.
    public static func compose(snapshot: TranscriptSnapshot, polished: String, polishedThrough: Int) -> LiveTranscript {
        var pending = String(snapshot.finalized.dropFirst(polishedThrough))
        var volatile = snapshot.volatile
        if pending.allSatisfy(\.isWhitespace) {
            pending = ""
            volatile = String(volatile.drop(while: \.isWhitespace))
        } else {
            pending = String(pending.drop(while: \.isWhitespace))
        }
        if volatile.allSatisfy(\.isWhitespace) { volatile = "" }

        // The polished text is trimmed, so put a space back between it and the raw text that follows.
        if let last = polished.last, !last.isWhitespace {
            if !pending.isEmpty {
                pending = " " + pending
            } else if !volatile.isEmpty {
                volatile = " " + volatile
            }
        }
        return LiveTranscript(polished: polished, pending: pending, volatile: volatile)
    }
}
