import Foundation

/// Spoken formatting commands, handled in code (not by the model) so they always work.
public enum SpokenCommands {
    public enum Break: String, Sendable, Equatable {
        case line = "\n"
        case paragraph = "\n\n"
    }

    public struct Segment: Sendable, Equatable {
        public var text: String
        /// The break the speaker asked for after this segment, if any.
        public var breakAfter: Break?

        public init(text: String, breakAfter: Break? = nil) {
            self.text = text
            self.breakAfter = breakAfter
        }
    }

    /// "new paragraph" / "new line", with whatever punctuation the transcriber put around them.
    private static let pattern = try! NSRegularExpression(
        // A comma before the command is dropped; a full stop / question mark before it belongs to the sentence.
        pattern: #"[,;:]?\s*\bnew (line|paragraph)\b[,.;:!?]?\s*"#,
        options: [.caseInsensitive])

    /// Splits a transcript at spoken break commands. Always returns at least one segment.
    public static func split(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var cursor = text.startIndex
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: text), let kind = Range(match.range(at: 1), in: text) else { continue }
            let piece = String(text[cursor..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let breakKind: Break = text[kind].lowercased() == "line" ? .line : .paragraph
            if piece.isEmpty, let last = segments.indices.last {
                // "new paragraph new paragraph" or a command at the very start: keep the strongest break.
                if segments[last].breakAfter != .paragraph { segments[last].breakAfter = breakKind }
            } else if !piece.isEmpty {
                segments.append(Segment(text: piece, breakAfter: breakKind))
            }
            cursor = range.upperBound
        }
        let rest = String(text[cursor...]).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty || segments.isEmpty { segments.append(Segment(text: rest)) }
        return segments
    }

    /// Re-joins (polished) segments, honouring breaks and capitalizing the start of each new line.
    public static func join(_ segments: [Segment]) -> String {
        var result = ""
        for segment in segments {
            var text = segment.text
            if result.hasSuffix("\n"), let first = text.first {
                text = first.uppercased() + text.dropFirst()
            } else if !result.isEmpty, !text.isEmpty {
                result += " "
            }
            result += text
            if let breakAfter = segment.breakAfter { result += breakAfter.rawValue }
        }
        return result
    }
}
