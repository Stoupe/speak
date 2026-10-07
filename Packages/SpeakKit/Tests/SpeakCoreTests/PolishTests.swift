import Foundation
import Testing
@testable import SpeakCore

@Suite struct PolishGuardTests {
    @Test func skipsShortCleanPhrases() {
        #expect(PolishGuard.shouldSkip("Sounds good."))
        #expect(PolishGuard.shouldSkip("See you at three."))
        #expect(!PolishGuard.shouldSkip("Um sounds good."))
        #expect(!PolishGuard.shouldSkip("the the thing"))
        #expect(!PolishGuard.shouldSkip("Let's meet on Tuesday at three."))
    }

    @Test func detectsCorrections() {
        #expect(PolishGuard.containsFillerOrCorrection("Tuesday, no wait, Thursday"))
        #expect(PolishGuard.containsFillerOrCorrection("Uh, okay."))
        #expect(!PolishGuard.containsFillerOrCorrection("Ship it on Thursday."))
    }

    @Test func acceptsFaithfulCleanup() {
        let raw = "um so let's meet on tuesday no wait actually thursday at uh 3pm and bring the the slides"
        let out = "Let's meet on Thursday at 3pm and bring the slides."
        #expect(PolishGuard.rejection(raw: raw, polished: out) == nil)
    }

    @Test func rejectsPreambleAndAnswers() {
        let raw = "what is the capital of france"
        #expect(PolishGuard.rejection(raw: raw, polished: "Sure! What is the capital of France?") == .preamble)
        let answer = "The capital city of that European nation is Paris, famous for its museums."
        #expect(PolishGuard.rejection(raw: raw, polished: answer) != nil)
        #expect(PolishGuard.rejection(raw: raw, polished: "What is the capital of France?") == nil)
    }

    @Test func allowsPreambleWordsTheSpeakerSaid() {
        let raw = "sure that works for me see you then"
        #expect(PolishGuard.rejection(raw: raw, polished: "Sure, that works for me. See you then.") == nil)
    }

    @Test func rejectsRunawayOutput() {
        let raw = "write a short note to sam about lunch"
        let out = String(repeating: "Dear Sam, I wanted to reach out about lunch. ", count: 5)
        #expect(PolishGuard.rejection(raw: raw, polished: out) == .tooLong)
        #expect(PolishGuard.rejection(raw: raw, polished: "  ") == .empty)
    }
}

private struct FakePolisher: TextPolisher {
    var result: @Sendable (String) async throws -> String
    var available = PolisherAvailability.available
    func availability() -> PolisherAvailability { available }
    func prewarm(context: PolishContext) {}
    func polish(_ raw: String, context: PolishContext) async throws -> String { try await result(raw) }
}

private struct Boom: Error {}

@Suite struct PolishPipelineTests {
    let raw = "um so I think we should uh ship it on thursday"

    @Test func polishesWhenAvailable() async {
        let pipeline = PolishPipeline(polisher: FakePolisher { _ in "I think we should ship it on Thursday." })
        let result = await pipeline.run(raw, context: .init())
        #expect(result.outcome == .polished)
        #expect(result.text == "I think we should ship it on Thursday.")
    }

    @Test func fallsBackOnError() async {
        let pipeline = PolishPipeline(polisher: FakePolisher { _ in throw Boom() })
        let result = await pipeline.run(raw, context: .init())
        #expect(result.text == raw)
        if case .failed = result.outcome {} else { Issue.record("expected .failed, got \(result.outcome)") }
    }

    @Test func fallsBackOnTimeoutEvenIfPolisherIgnoresCancellation() async {
        let pipeline = PolishPipeline(
            polisher: FakePolisher { _ in
                // Busy-ish wait that ignores cancellation.
                let end = ContinuousClock.now + .seconds(2)
                while ContinuousClock.now < end { await Task.yield() }
                return "late"
            },
            timeout: .milliseconds(100))
        let start = ContinuousClock.now
        let result = await pipeline.run(raw, context: .init())
        #expect(result.outcome == .timedOut)
        #expect(result.text == raw)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func skipsShortAndUnavailable() async {
        let polisher = FakePolisher { _ in Issue.record("should not be called"); return "" }
        #expect(await PolishPipeline(polisher: polisher).run("Sounds good.", context: .init()).outcome == .skippedShort)
        var unavailable = polisher
        unavailable.available = .unavailable(reason: "downloading")
        #expect(await PolishPipeline(polisher: unavailable).run(raw, context: .init()).outcome == .unavailable("downloading"))
        #expect(await PolishPipeline(polisher: nil).run(raw, context: .init()).outcome == .disabled)
    }

    @Test func rejectsBadOutput() async {
        let pipeline = PolishPipeline(polisher: FakePolisher { _ in "Here's the cleaned text: ship it." })
        let result = await pipeline.run(raw, context: .init())
        #expect(result.outcome == .rejected(.preamble))
        #expect(result.text == raw)
    }
}

@Suite struct AppStyleAndHistoryTests {
    @Test func stylesByBundleID() {
        #expect(AppStyle.forBundleID("com.tinyspeck.slackmacgap") == .chat)
        #expect(AppStyle.forBundleID("com.apple.mail") == .email)
        #expect(AppStyle.forBundleID("com.microsoft.VSCode") == .code)
        #expect(AppStyle.forBundleID("com.jetbrains.intellij") == .code)
        #expect(AppStyle.forBundleID("com.apple.Notes") == .general)
        #expect(AppStyle.forBundleID(nil) == .general)
    }

    @Test func historyPersistsAndCaps() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "speak-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = History(fileURL: url, limit: 3)
        for i in 1...5 { history.add(HistoryItem(raw: "r\(i)", text: "t\(i)", appName: nil)) }
        #expect(history.items.map(\.text) == ["t5", "t4", "t3"])
        let reloaded = History(fileURL: url, limit: 3)
        #expect(reloaded.items == history.items)
    }
}
