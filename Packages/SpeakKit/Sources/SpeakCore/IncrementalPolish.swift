import Foundation

/// Polishes a dictation in pieces while it's still being spoken, so releasing the key only waits for the
/// last piece, however long the dictation was.
///
/// Feed it the growing *finalized* transcript with `update(finalized:)`. Whenever enough complete sentences
/// have built up, they're cut off and polished in the background (one piece at a time). `finish` polishes
/// whatever is left and returns the assembled text.
public actor IncrementalPolish {
    public struct Result: Sendable {
        public var text: String
        /// One outcome per polished segment, in order.
        public var outcomes: [PolishPipeline.Outcome]
    }

    private let pipeline: PolishPipeline
    private let context: PolishContext
    private let minimumPiece: Int

    /// Offset (in Characters) into the finalized transcript up to which pieces have been handed off.
    private var committed = 0
    private var finalized = ""
    private var pieces: [Task<[(SpokenCommands.Segment, PolishPipeline.Outcome)], Never>] = []

    /// - Parameter minimumPiece: Characters of finished sentences to collect before polishing a piece.
    public init(pipeline: PolishPipeline, context: PolishContext, minimumPiece: Int = 120) {
        self.pipeline = pipeline
        self.context = context
        self.minimumPiece = minimumPiece
    }

    public func update(finalized text: String) {
        finalized = text
        let pending = String(text.dropFirst(committed))
        guard let cut = Self.cutPoint(in: pending, minimum: minimumPiece) else { return }
        let piece = String(pending[..<cut])
        committed += piece.count
        enqueue(piece)
    }

    /// Polishes the remainder and returns the whole dictation.
    public func finish(transcript: String) async -> Result {
        // Finalized text only grows, so the final transcript should start with what we've already cut.
        // If it somehow doesn't, polish the remainder from wherever the committed text ends.
        let alreadyCut = String(finalized.prefix(committed))
        let remainder = transcript.hasPrefix(alreadyCut)
            ? String(transcript.dropFirst(committed))
            : String(transcript.dropFirst(min(committed, transcript.count)))
        if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { enqueue(remainder) }

        var segments: [SpokenCommands.Segment] = []
        var outcomes: [PolishPipeline.Outcome] = []
        for piece in pieces {
            for (segment, outcome) in await piece.value {
                segments.append(segment)
                outcomes.append(outcome)
            }
        }
        return Result(text: SpokenCommands.join(segments), outcomes: outcomes)
    }

    public func cancel() {
        pieces.forEach { $0.cancel() }
        pieces = []
    }

    /// Pieces are polished one after another: the on-device model handles one request at a time.
    private func enqueue(_ piece: String) {
        let previous = pieces.last
        let pipeline = pipeline
        let context = context
        pieces.append(Task {
            _ = await previous?.value
            var results: [(SpokenCommands.Segment, PolishPipeline.Outcome)] = []
            for var segment in SpokenCommands.split(piece) {
                let result = await pipeline.run(segment.text, context: context)
                segment.text = result.text
                results.append((segment, result.outcome))
            }
            // Ready the model for the next piece while the user keeps talking.
            pipeline.polisher?.prewarm(context: context)
            return results
        })
    }

    /// Where to cut `pending`: after the last sentence end that leaves at least `minimum` characters before it
    /// and has the start of another sentence after it. Never cuts right before a self-correction
    /// ("Actually…", "No wait…"), which needs the previous sentence to make sense.
    static func cutPoint(in pending: String, minimum: Int) -> String.Index? {
        guard pending.count > minimum else { return nil }
        var best: String.Index?
        var index = pending.startIndex
        while index < pending.endIndex {
            let character = pending[index]
            let next = pending.index(after: index)
            if ".?!".contains(character), next < pending.endIndex, pending[next].isWhitespace {
                let following = pending[next...].drop(while: \.isWhitespace)
                if pending.distance(from: pending.startIndex, to: next) >= minimum,
                   !following.isEmpty,
                   !startsWithCorrection(following) {
                    best = next
                }
            }
            index = next
        }
        return best
    }

    static func startsWithCorrection(_ text: Substring) -> Bool {
        let lower = text.prefix(24).lowercased()
        return correctionStarts.contains { lower.hasPrefix($0) }
    }

    private static let correctionStarts = [
        "actually", "no wait", "no,", "no.", "wait", "sorry", "scratch that", "i mean", "or rather", "make that",
        "correction",
    ]
}
