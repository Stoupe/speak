import Foundation
import Testing
@testable import SpeakCore

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

    @Test func cancelStopsFurtherWork() async throws {
        let polisher = RecordingPolisher(delay: .milliseconds(50))
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 50)
        await incremental.cancel()
        await incremental.update(finalized: String(repeating: "This is a sentence of decent length. ", count: 6))
        try await Task.sleep(for: .milliseconds(100))
        #expect(polisher.calls.withLock { $0.isEmpty })
    }

    @Test func reportsEachPolishedPiece() async throws {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 100)
        let finalized = String(repeating: sentence, count: 3)
        await incremental.update(finalized: finalized)

        var iterator = incremental.progress.makeAsyncIterator()
        let progress = try #require(await iterator.next())
        let cut = String(finalized.prefix(progress.rawThrough))
        #expect(progress.polished == cut.trimmingCharacters(in: .whitespaces).uppercased())
        #expect(finalized.dropFirst(progress.rawThrough).trimmingCharacters(in: .whitespaces) == sentence.trimmingCharacters(in: .whitespaces))
    }

    @Test func spokenCommandsAreJustWords() async {
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: nil), context: .init())
        let result = await incremental.finish(transcript: "Hi Sam, new paragraph. Thanks.")
        #expect(result.text == "Hi Sam, new paragraph. Thanks.")
    }

    @Test func piecesKeepLineBreaksFromTheModel() {
        #expect(IncrementalPolish.join("Hi Sam,\n", "Thanks.") == "Hi Sam,\nThanks.")
        #expect(IncrementalPolish.join("One.", "Two.") == "One. Two.")
        #expect(IncrementalPolish.join("", "Two.") == "Two.")
    }
}

@Suite struct LiveTranscriptTests {
    @Test func splitsPolishedPendingAndVolatile() {
        let snapshot = TranscriptSnapshot(finalized: "um hello there. how are you", volatile: " doing today")
        let live = LiveTranscript.compose(snapshot: snapshot, polished: "Hello there.", polishedThrough: 15)
        #expect(live == LiveTranscript(polished: "Hello there.", pending: " how are you", volatile: " doing today"))
    }

    @Test func spacesVolatileAfterPolishedText() {
        let snapshot = TranscriptSnapshot(finalized: "Hello there. ", volatile: " how")
        let live = LiveTranscript.compose(snapshot: snapshot, polished: "Hello there.", polishedThrough: 13)
        #expect(live == LiveTranscript(polished: "Hello there.", volatile: " how"))
    }

    @Test func startsWithoutLeadingSpace() {
        let live = LiveTranscript.compose(snapshot: .init(volatile: " hello"), polished: "", polishedThrough: 0)
        #expect(live == LiveTranscript(volatile: "hello"))
        #expect(LiveTranscript.compose(snapshot: .init(), polished: "", polishedThrough: 0).isEmpty)
    }

    @Test func noSpaceAfterALineBreak() {
        let live = LiveTranscript.compose(snapshot: .init(finalized: "Hi Sam. thanks"), polished: "Hi Sam,\n", polishedThrough: 7)
        #expect(live == LiveTranscript(polished: "Hi Sam,\n", pending: "thanks"))
    }
}
