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

    @Test func cutsAsSoonAsASentenceIsFinished() {
        let pending = String(repeating: "Some words here. ", count: 10).trimmingCharacters(in: .whitespaces)
        #expect(IncrementalPolish.cutPoint(in: pending, minimum: 50) == pending.endIndex)
        // Not mid-sentence, and not before there's enough text.
        #expect(IncrementalPolish.cutPoint(in: pending + " And then", minimum: 50) == pending.endIndex)
        #expect(IncrementalPolish.cutPoint(in: "Short. Text.", minimum: 50) == nil)
    }

    @Test func aLateCorrectionIsPolishedWithTheSentenceItCorrects() async throws {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 50)
        let first = "Let's meet on Tuesday at the usual place near the office."
        await incremental.update(finalized: first)
        try await Task.sleep(for: .milliseconds(100))
        #expect(polisher.calls.withLock { $0 } == [first])

        let corrected = first + " Actually, make that Wednesday."
        await incremental.update(finalized: corrected)
        let result = await incremental.finish(transcript: corrected)
        #expect(polisher.calls.withLock { $0 } == [first, corrected])
        #expect(result.text == corrected.uppercased())
    }

    @Test func afterReleaseTheRestIsPolishedInOneCall() async {
        let polisher = RecordingPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 50)
        await incremental.endOfSpeech()
        let text = String(repeating: sentence, count: 3).trimmingCharacters(in: .whitespaces)
        await incremental.update(finalized: text)
        let result = await incremental.finish(transcript: text)
        #expect(polisher.calls.withLock { $0 } == [text])
        #expect(result.text == text.uppercased())
    }

    @Test func piecesStillQueuedJoinTheFinalCall() async throws {
        let polisher = RecordingPolisher(delay: .milliseconds(200))
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: .init(), minimumPiece: 50)
        let one = sentence.trimmingCharacters(in: .whitespaces)
        await incremental.update(finalized: one)
        try await Task.sleep(for: .milliseconds(20))
        // Queued behind the first piece, which the model is still working on.
        await incremental.update(finalized: one + " " + one)
        let all = [one, one, "And a final remark."].joined(separator: " ")
        let result = await incremental.finish(transcript: all)
        #expect(polisher.calls.withLock { $0 } == [one, one + " And a final remark."])
        #expect(result.text == all.uppercased())
    }

    @Test func longRemaindersAreSplitAtSentences() {
        let text = String(repeating: "Here is one more sentence. ", count: 12).trimmingCharacters(in: .whitespaces)
        let parts = IncrementalPolish.split(text, longest: 100)
        #expect(parts.count == 4)
        #expect(parts.allSatisfy { $0.count <= 100 })
        #expect(parts.joined() == text)
        #expect(IncrementalPolish.split("Short.", longest: 100) == ["Short."])
    }

    @Test func piecesPolishedWhileSpeakingGetLonger() {
        let pipeline = PolishPipeline(polisher: nil, timeout: .seconds(2), timeoutPerCharacter: .milliseconds(10), maxTimeout: .seconds(8))
        let relaxed = pipeline.withTimeoutsScaled(by: 2)
        #expect(relaxed.timeout(for: String(repeating: "a", count: 100)) == .seconds(6))
        #expect(relaxed.timeout(for: String(repeating: "a", count: 1000)) == .seconds(16))
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
        let finished = finalized.trimmingCharacters(in: .whitespaces)
        #expect(progress.polished == finished.uppercased())
        #expect(progress.rawThrough == finished.count)
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
