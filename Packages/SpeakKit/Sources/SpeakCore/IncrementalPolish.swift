import Foundation

/// Polishes a dictation in pieces while it's still being spoken, so releasing the key only waits for the
/// last piece, however long the dictation was.
///
/// Feed it the growing *finalized* transcript with `update(finalized:)`. Whenever enough complete sentences
/// have built up, they're cut off and polished in the background (one piece at a time). `progress` reports
/// each finished piece, so the cleaned-up text can be shown while the user keeps talking. `finish` polishes
/// whatever is left and returns the assembled text.
public actor IncrementalPolish {
    public struct Result: Sendable {
        public var text: String
        /// One outcome per polished piece, in order.
        public var outcomes: [PolishPipeline.Outcome]
    }

    /// The polished text so far.
    public struct Progress: Sendable, Equatable {
        public var polished = ""
        /// How many characters of the finalized transcript `polished` covers.
        public var rawThrough = 0

        public init(polished: String = "", rawThrough: Int = 0) {
            self.polished = polished
            self.rawThrough = rawThrough
        }
    }

    private struct Piece: Sendable {
        var text: String
        var outcome: PolishPipeline.Outcome
    }

    /// Updated after each piece is polished; ends when the dictation finishes or is cancelled.
    public nonisolated let progress: AsyncStream<Progress>
    private let progressContinuation: AsyncStream<Progress>.Continuation

    private let pipeline: PolishPipeline
    private let context: PolishContext
    private let minimumPiece: Int

    /// Offset (in Characters) into the finalized transcript up to which pieces have been handed off.
    private var committed = 0
    private var finalized = ""
    private var pieces: [Task<Piece, Never>] = []
    private var done = Progress()
    /// Bumped when queued pieces are thrown away, so their late results are ignored.
    private var generation = 0
    private var isCancelled = false

    /// - Parameter minimumPiece: Characters of finished sentences to collect before polishing a piece.
    public init(pipeline: PolishPipeline, context: PolishContext, minimumPiece: Int = 120) {
        self.pipeline = pipeline
        self.context = context
        self.minimumPiece = minimumPiece
        (progress, progressContinuation) = AsyncStream<Progress>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func update(finalized text: String) {
        guard !isCancelled else { return }
        finalized = text
        let pending = String(text.dropFirst(committed))
        guard let cut = Self.cutPoint(in: pending, minimum: minimumPiece) else { return }
        let piece = String(pending[..<cut])
        committed += piece.count
        enqueue(piece, rawThrough: committed)
    }

    /// Polishes the remainder and returns the whole dictation.
    public func finish(transcript: String) async -> Result {
        defer { progressContinuation.finish() }
        // Finalized text only grows, so the final transcript should start with what we've already cut.
        // If it somehow doesn't, throw the pieces away and polish the whole transcript in one go.
        let alreadyCut = String(finalized.prefix(committed))
        let remainder: String
        if transcript.hasPrefix(alreadyCut) {
            remainder = String(transcript.dropFirst(committed))
        } else {
            discardPieces()
            remainder = transcript
        }
        if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            enqueue(remainder, rawThrough: transcript.count)
        }

        var text = ""
        var outcomes: [PolishPipeline.Outcome] = []
        for piece in pieces {
            let piece = await piece.value
            text = Self.join(text, piece.text)
            outcomes.append(piece.outcome)
        }
        return Result(text: text, outcomes: outcomes)
    }

    public func cancel() {
        isCancelled = true
        discardPieces()
        progressContinuation.finish()
    }

    private func discardPieces() {
        pieces.forEach { $0.cancel() }
        pieces = []
        generation += 1
        done = Progress()
    }

    /// Pieces are polished one after another: the on-device model handles one request at a time.
    private func enqueue(_ piece: String, rawThrough: Int) {
        let previous = pieces.last
        let pipeline = pipeline
        let context = context
        let generation = generation
        pieces.append(Task {
            _ = await previous?.value
            guard !Task.isCancelled else { return Piece(text: "", outcome: .disabled) }
            let result = await pipeline.run(piece, context: context)
            pieceFinished(result.text, rawThrough: rawThrough, generation: generation)
            // Ready the model for the next piece while the user keeps talking.
            if !Task.isCancelled { pipeline.polisher?.prewarm(context: context) }
            return Piece(text: result.text, outcome: result.outcome)
        })
    }

    private func pieceFinished(_ text: String, rawThrough: Int, generation: Int) {
        guard generation == self.generation, !isCancelled else { return }
        done.polished = Self.join(done.polished, text)
        done.rawThrough = rawThrough
        progressContinuation.yield(done)
    }

    /// Joins polished pieces with a space, unless the model ended or started one with a line break.
    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last else { return tail }
        guard let first = tail.first else { return head }
        return last.isNewline || first.isNewline ? head + tail : head + " " + tail
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
