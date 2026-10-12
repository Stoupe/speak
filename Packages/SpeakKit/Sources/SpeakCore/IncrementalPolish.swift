import Foundation

/// Polishes a dictation in pieces while it's still being spoken, so releasing the key only waits for what was
/// said last, however long the dictation was.
///
/// Feed it the growing *finalized* transcript with `update(finalized:)`. As soon as enough finished sentences
/// have built up, they're cut off and polished in the background (one piece at a time). `progress` reports
/// each finished piece, so the cleaned-up text can be shown while the user keeps talking. Call `endOfSpeech()`
/// when the user lets go, then `finish` polishes whatever is left in one go and returns the assembled text.
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

    private struct Polished: Sendable {
        var text: String
        var outcome: PolishPipeline.Outcome
    }

    private struct Piece {
        let id: Int
        let raw: String
        /// Characters of the finalized transcript up to the end of this piece.
        let rawThrough: Int
        /// Nil if the piece was withdrawn before or while the model worked on it.
        let task: Task<Polished?, Never>
    }

    /// Updated after each piece is polished; ends when the dictation finishes or is cancelled.
    public nonisolated let progress: AsyncStream<Progress>
    private let progressContinuation: AsyncStream<Progress>.Continuation

    /// For what's left after the user lets go: they're waiting, so time limits are tight.
    private let pipeline: PolishPipeline
    /// For pieces polished while the user is still talking: nobody is waiting on them yet, so they get longer
    /// before falling back to raw text.
    private let speakingPipeline: PolishPipeline
    private let context: PolishContext
    private let minimumPiece: Int
    /// What's left at the end is polished in one call (less overhead than several) unless it's longer than
    /// this; long text is where the model starts to summarize.
    private let maximumFinalPiece: Int

    private var finalized = ""
    /// Offset (in Characters) into the finalized transcript up to which pieces have been handed off.
    private var committed = 0
    private var pieces: [Piece] = []
    private var results: [Int: Polished] = [:]
    /// Pieces the model has started on. Ones that haven't started can still be merged into the final call.
    private var started: Set<Int> = []
    private var nextID = 0
    /// The most recently queued task, even if since withdrawn: the on-device model handles one request at a
    /// time, so every piece waits for it.
    private var lastTask: Task<Polished?, Never>?
    private var isSpeaking = true
    private var isCancelled = false

    /// - Parameters:
    ///   - minimumPiece: Characters of finished sentences to collect before polishing a piece.
    ///   - speakingTimeoutScale: How much longer than `pipeline`'s time limits pieces polished while the user
    ///     is still talking may take.
    public init(
        pipeline: PolishPipeline,
        context: PolishContext,
        minimumPiece: Int = 120,
        maximumFinalPiece: Int = 360,
        speakingTimeoutScale: Int = 2
    ) {
        self.pipeline = pipeline
        self.speakingPipeline = pipeline.withTimeoutsScaled(by: speakingTimeoutScale)
        self.context = context
        self.minimumPiece = minimumPiece
        self.maximumFinalPiece = maximumFinalPiece
        (progress, progressContinuation) = AsyncStream<Progress>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func update(finalized text: String) {
        guard !isCancelled else { return }
        finalized = text
        guard isSpeaking else { return }
        reopenIfCorrected()
        let pending = String(text.dropFirst(committed))
        guard let cut = Self.cutPoint(in: pending, minimum: minimumPiece) else { return }
        enqueue(String(pending[..<cut]), pipeline: speakingPipeline)
    }

    /// The user has let go: stop cutting pieces, so the last of the transcript is polished in one call.
    public func endOfSpeech() {
        isSpeaking = false
    }

    /// Polishes the remainder and returns the whole dictation.
    public func finish(transcript: String) async -> Result {
        isSpeaking = false
        defer { progressContinuation.finish() }
        // Finalized text only grows, so the final transcript should start with what we've already cut.
        // If it somehow doesn't, throw the pieces away and polish the whole transcript afresh.
        if !transcript.hasPrefix(finalized.prefix(committed)) {
            while let last = pieces.last { withdraw(last) }
        }
        finalized = transcript
        reopenIfCorrected()
        // Pieces still queued behind the model join the remainder.
        while let last = pieces.last, !started.contains(last.id) { withdraw(last) }

        let remainder = String(transcript.dropFirst(committed))
        if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for part in Self.split(remainder, longest: maximumFinalPiece) { enqueue(part, pipeline: pipeline) }
        }

        var text = ""
        var outcomes: [PolishPipeline.Outcome] = []
        for piece in pieces {
            guard let polished = await piece.task.value else { continue }
            text = Self.join(text, polished.text)
            outcomes.append(polished.outcome)
        }
        return Result(text: text, outcomes: outcomes)
    }

    public func cancel() {
        isCancelled = true
        while let last = pieces.last { withdraw(last) }
        progressContinuation.finish()
    }

    // MARK: Pieces

    private func enqueue(_ raw: String, pipeline: PolishPipeline) {
        let id = nextID
        nextID += 1
        committed += raw.count
        let previous = lastTask
        let context = context
        let task = Task<Polished?, Never> {
            _ = await previous?.value
            guard claim(id) else { return nil }
            let result = await pipeline.run(raw, context: context)
            // Ready the model for the next piece while the user keeps talking.
            if !Task.isCancelled { pipeline.polisher?.prewarm(context: context) }
            let polished = Polished(text: result.text, outcome: result.outcome)
            return record(polished, for: id) ? polished : nil
        }
        pieces.append(Piece(id: id, raw: raw, rawThrough: committed, task: task))
        lastTask = task
    }

    /// Called as the model is about to start on a piece; false if it has been withdrawn meanwhile.
    private func claim(_ id: Int) -> Bool {
        guard !Task.isCancelled, pieces.contains(where: { $0.id == id }) else { return false }
        started.insert(id)
        return true
    }

    /// Keeps a finished piece's text, unless the piece was withdrawn while the model worked on it.
    private func record(_ polished: Polished, for id: Int) -> Bool {
        guard pieces.contains(where: { $0.id == id }) else { return false }
        results[id] = polished
        publishProgress()
        return true
    }

    /// Takes the last piece back, so its text is polished again as part of a later piece.
    private func withdraw(_ piece: Piece) {
        piece.task.cancel()
        pieces.removeLast()
        results[piece.id] = nil
        committed = pieces.last?.rawThrough ?? 0
        publishProgress()
    }

    /// "Actually, make that Friday" only makes sense with the sentence it corrects, so when the text after the
    /// last piece starts with a correction, that piece is put back and polished again together with it.
    private func reopenIfCorrected() {
        guard let last = pieces.last,
              Self.startsWithCorrection(finalized.dropFirst(committed).drop(while: \.isWhitespace))
        else { return }
        withdraw(last)
    }

    /// The polished text of the finished pieces at the start of the dictation.
    private func publishProgress() {
        guard !isCancelled else { return }
        var progress = Progress()
        for piece in pieces {
            guard let polished = results[piece.id] else { break }
            progress.polished = Self.join(progress.polished, polished.text)
            progress.rawThrough = piece.rawThrough
        }
        progressContinuation.yield(progress)
    }

    // MARK: Text

    /// Joins polished pieces with a space, unless the model ended or started one with a line break.
    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last else { return tail }
        guard let first = tail.first else { return head }
        return last.isNewline || first.isNewline ? head + tail : head + " " + tail
    }

    /// Where to cut `pending`: after the last sentence end that leaves at least `minimum` characters before it,
    /// including the very end of `pending`. Never cuts right before a self-correction ("Actually…",
    /// "No wait…"), which needs the previous sentence to make sense; a correction that arrives after the cut
    /// puts the piece back (see `reopenIfCorrected`).
    static func cutPoint(in pending: String, minimum: Int) -> String.Index? {
        guard pending.count >= minimum else { return nil }
        var best: String.Index?
        var index = pending.startIndex
        var offset = 0
        while index < pending.endIndex {
            let next = pending.index(after: index)
            offset += 1
            if offset >= minimum, ".?!".contains(pending[index]) {
                if next == pending.endIndex {
                    best = next
                } else if pending[next].isWhitespace {
                    let following = pending[next...].drop(while: \.isWhitespace)
                    if following.isEmpty || !startsWithCorrection(following) { best = next }
                }
            }
            index = next
        }
        return best
    }

    /// Splits `text` at sentence ends into parts of roughly equal length, none longer than `longest` unless
    /// there's no sentence end to split at.
    static func split(_ text: String, longest: Int) -> [String] {
        let count = text.count
        guard count > longest else { return [text] }
        let target = count / ((count + longest - 1) / longest)
        var parts: [String] = []
        var rest = Substring(text)
        while rest.count > longest, let cut = firstSentenceEnd(in: rest, from: target) {
            parts.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        parts.append(String(rest))
        return parts
    }

    /// The first sentence end at least `minimum` characters in, with more text after it.
    private static func firstSentenceEnd(in text: Substring, from minimum: Int) -> String.Index? {
        var index = text.startIndex
        var offset = 0
        while index < text.endIndex {
            let next = text.index(after: index)
            offset += 1
            if offset >= minimum, ".?!".contains(text[index]), next < text.endIndex, text[next].isWhitespace {
                let following = text[next...].drop(while: \.isWhitespace)
                if !following.isEmpty, !startsWithCorrection(following) { return next }
            }
            index = next
        }
        return nil
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
