import Foundation
import Testing
@testable import SpeakCore

@Suite struct SpokenCommandsTests {
    @Test func splitsOnCommandsWithTranscriberPunctuation() {
        let segments = SpokenCommands.split("Hi Sam. New paragraph. Thanks for this, new line. Henry")
        #expect(segments == [
            .init(text: "Hi Sam.", breakAfter: .paragraph),
            .init(text: "Thanks for this", breakAfter: .line),
            .init(text: "Henry"),
        ])
        #expect(SpokenCommands.join(segments) == "Hi Sam.\n\nThanks for this\nHenry")
    }

    @Test func noCommandsIsOneSegment() {
        #expect(SpokenCommands.split("Just a sentence.") == [.init(text: "Just a sentence.")])
        #expect(SpokenCommands.split("") == [.init(text: "")])
    }

    @Test func joinCapitalizesAfterBreaks() {
        let joined = SpokenCommands.join([
            .init(text: "first point", breakAfter: .line), .init(text: "second point"),
        ])
        #expect(joined == "first point\nSecond point")
    }
}

/// Uppercases its input after a short delay and records what it was asked to polish.
private final class RecordingPolisher: TextPolisher, @unchecked Sendable {
    let calls = Locked<[String]>([])
    let delay: Duration

    init(delay: Duration = .milliseconds(20)) { self.delay = delay }

    func availability() -> PolisherAvailability { .available }
    func prewarm(context: PolishContext) {}
    func polish(_ raw: String, context: PolishContext) async throws -> String {
        calls.withLock { $0.append(raw) }
        try await Task.sleep(for: delay)
        return raw.uppercased()
    }
}

@Suite struct IncrementalPolishTests {
    let sentence = "This is a reasonably long sentence about the project status. "

    @Test func shortDictationIsPolishedOnceAtTheEnd() async {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 200)
        await incremental.update(finalized: "um so this is short and fine.")
        let result = await incremental.finish(transcript: "um so this is short and fine.")
        #expect(result.text == "UM SO THIS IS SHORT AND FINE.")
        #expect(polisher.calls.withLock { $0.count } == 1)
    }

    @Test func longDictationIsPolishedInPiecesWhileSpeaking() async throws {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 100)
        var finalized = ""
        for _ in 0..<6 {
            finalized += sentence
            await incremental.update(finalized: finalized)
        }
        try await Task.sleep(for: .milliseconds(200))
        let polishedBeforeRelease = polisher.calls.withLock { $0.count }
        #expect(polishedBeforeRelease >= 2)

        let result = await incremental.finish(transcript: finalized.trimmingCharacters(in: .whitespaces))
        #expect(result.text == finalized.trimmingCharacters(in: .whitespaces).uppercased())
        #expect(result.outcomes.allSatisfy { $0 == .polished })
    }

    @Test func neverCutsBeforeASelfCorrection() {
        let pending = String(repeating: "Some words here. ", count: 8) + "Actually, make that Friday. And more."
        let cut = IncrementalPolish.cutPoint(in: pending, minimum: 50)!
        let following = pending[cut...].trimmingCharacters(in: .whitespaces)
        #expect(!following.hasPrefix("Actually"))
        #expect(pending[..<cut].contains("Actually"))
    }

    @Test func waitsForTheNextSentenceBeforeCutting() {
        let pending = String(repeating: "Some words here. ", count: 10)
        // Ends on a sentence boundary with nothing after: the last sentence can't be judged yet,
        // so the cut lands before it.
        let cut = IncrementalPolish.cutPoint(in: pending.trimmingCharacters(in: .whitespaces), minimum: 50)!
        #expect(pending[cut...].trimmingCharacters(in: .whitespaces) == "Some words here.")
    }

    @Test func spokenCommandsBecomeBreaks() async {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init())
        let result = await incremental.finish(
            transcript: "um hi sam, new paragraph. thanks for the notes, they were uh really useful. new line. henry")
        // Short clean segments skip the model (see PolishGuard.shouldSkip); breaks still apply.
        #expect(result.text == "UM HI SAM\n\nTHANKS FOR THE NOTES, THEY WERE UH REALLY USEFUL.\nHenry")
    }
}
