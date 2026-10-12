import AVFAudio
import Foundation
import SpeakCore
import SpeakEngines

// Headless harness for the engines. Nothing here touches the keyboard, clipboard or screen.
//
//   speak-bench status
//   speak-bench transcribe [--realtime] <audio>...      transcript + latency after end of audio
//   speak-bench polish [--style chat|email|code] <text> polish one string
//   speak-bench cases <cases.json> [--style …]          polish every {"raw": …, "expected": …} case
//   speak-bench run [--realtime] <audio>...             transcribe, then polish
//   speak-bench long <text>                             simulate a long dictation polished while speaking
//   speak-bench trace <audio>                           stream audio in real time like the app; timeline of
//                                                       finalized text, polish calls and the wait after release

@main
struct SpeakBench {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { return usage() }
        let command = args.removeFirst()
        let realtime = take("--realtime", from: &args)
        let style = takeValue("--style", from: &args).flatMap(AppStyle.init(rawValue:)) ?? .general
        let context = PolishContext(appName: nil, style: style, vocabulary: [])

        do {
            switch command {
            case "status":
                print("Polisher:", FoundationModelsPolisher().availability())
                let transcriber = AppleSpeechTranscriber()
                let start = ContinuousClock.now
                try await transcriber.prepare()
                print("Transcriber: ready (prepare took \(ContinuousClock.now - start))")
            case "transcribe", "run":
                let transcriber = AppleSpeechTranscriber()
                try await transcriber.prepare()
                let pipeline = PolishPipeline(polisher: FoundationModelsPolisher(), timeout: .seconds(10))
                for path in args {
                    let (raw, tail) = try await transcribe(path, with: transcriber, realtime: realtime)
                    print("\n▸ \(path)\n  raw  (\(tail) after end of audio): \(raw)")
                    if command == "run" {
                        let result = await pipeline.run(raw, context: context)
                        print("  out  (\(result.duration), \(result.outcome)): \(result.text)")
                    }
                }
            case "polish":
                let pipeline = PolishPipeline(polisher: FoundationModelsPolisher(), timeout: .seconds(10))
                let result = await pipeline.run(args.joined(separator: " "), context: context)
                print("\(result.outcome) in \(result.duration):\n\(result.text)")
            case "trace":
                guard let path = args.first else { return usage() }
                try await runTrace(path, context: context)
            case "long":
                try await runLong(args.joined(separator: " "), context: context)
            case "cases":
                guard let path = args.first else { return usage() }
                try await runCases(path, context: context)
            default:
                usage()
            }
        } catch {
            print("error:", error)
            exit(1)
        }
    }

    static func transcribe(
        _ path: String, with transcriber: AppleSpeechTranscriber, realtime: Bool
    ) async throws -> (String, Duration) {
        let file = try AVAudioFile(forReading: URL(filePath: path))
        let session = try transcriber.begin(vocabulary: [])
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10) // 100 ms, like a mic tap
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            session.append(buffer)
            if realtime { try await Task.sleep(for: .milliseconds(100)) }
        }
        let end = ContinuousClock.now
        let text = try await session.finish()
        return (text, ContinuousClock.now - end)
    }

    struct Case: Decodable {
        var raw: String
        var expected: String?
        var style: String?
    }

    static func runCases(_ path: String, context: PolishContext) async throws {
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(filePath: path)))
        let polisher = FoundationModelsPolisher()
        let pipeline = PolishPipeline(polisher: polisher, timeout: .seconds(10))
        var exact = 0
        var total = Duration.zero
        for (index, item) in cases.enumerated() {
            var context = context
            if let style = item.style.flatMap(AppStyle.init(rawValue:)) { context.style = style }
            // Like the app: prewarm on Fn down, then the user talks for a moment before releasing.
            polisher.prewarm(context: context)
            try await Task.sleep(for: .seconds(1.5))
            let result = await pipeline.run(item.raw, context: context)
            total += result.duration
            let match = item.expected.map { $0 == result.text }
            if match == true { exact += 1 }
            print("""

            #\(index + 1) [\(context.style.rawValue)] \(result.outcome) in \(result.duration)\(match == false ? "  ≠ expected" : "")
              raw: \(item.raw)
              out: \(result.text)
            """)
            if match == false, let expected = item.expected { print("  exp: \(expected)") }
        }
        print("\n\(exact)/\(cases.count) exact matches, average \(total / cases.count)")
    }

    /// Feeds `text` to IncrementalPolish one sentence at a time at ~150 wpm, then reports the wait after "release".
    static func runLong(_ text: String, context: PolishContext) async throws {
        let polisher = FoundationModelsPolisher()
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: context)
        polisher.prewarm(context: context)

        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence { sentences.append(sentence) }
        }
        var finalized = ""
        let speakingStart = ContinuousClock.now
        for sentence in sentences {
            // ~150 words per minute is ~15 characters per second.
            try await Task.sleep(for: .milliseconds(sentence.count * 1000 / 15))
            finalized += sentence
            await incremental.update(finalized: finalized)
        }
        print("spoke \(sentences.count) sentences in \(ContinuousClock.now - speakingStart)")
        let release = ContinuousClock.now
        let result = await incremental.finish(transcript: finalized.trimmingCharacters(in: .whitespaces))
        print("wait after release: \(ContinuousClock.now - release)")
        print("outcomes: \(result.outcomes)")
        print("\n\(result.text)")
    }

    /// Streams an audio file in real time through the transcriber and `IncrementalPolish`, as the app does,
    /// printing when text is finalized, when each piece is polished, and how long "release" waits.
    static func runTrace(_ path: String, context: PolishContext) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let stamp: @Sendable () -> String = {
            let elapsed = (clock.now - start).components
            return String(format: "%6.2fs", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }

        let transcriber = AppleSpeechTranscriber()
        try await transcriber.prepare()
        let polisher = TimedPolisher(FoundationModelsPolisher(), stamp: stamp)
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polisher), context: context)
        polisher.prewarm(context: context)

        let file = try AVAudioFile(forReading: URL(filePath: path))
        print("audio \(String(format: "%.1f", Double(file.length) / file.processingFormat.sampleRate))s")
        let session = try transcriber.begin(vocabulary: [])
        let finalized = session.finalized
        let partials = session.partials
        let progress = incremental.progress
        let feed = Task {
            for await text in finalized {
                print("\(stamp())  finalized → \(text.count) chars")
                await incremental.update(finalized: text)
            }
        }
        let longestVolatile = Task {
            var longest = 0
            for await snapshot in partials { longest = max(longest, snapshot.volatile.count) }
            return longest
        }
        let pieces = Task {
            for await done in progress { print("\(stamp())  polished through \(done.rawThrough) chars") }
        }

        // 100 ms buffers, like the mic tap, paced to real time.
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        let audioStart = clock.now
        var sent = 0.0
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            session.append(buffer)
            sent += Double(buffer.frameLength) / file.processingFormat.sampleRate
            try await Task.sleep(until: audioStart + .milliseconds(Int(sent * 1000)))
        }
        print("\(stamp())  ── release ──")
        let release = clock.now
        await incremental.endOfSpeech()
        let raw = try await session.finish()
        print("\(stamp())  transcript final (\(raw.count) chars) after \(clock.now - release)")
        await feed.value
        let result = await incremental.finish(transcript: raw)
        await pieces.value
        print("\(stamp())  done; waited \(clock.now - release) after release")
        print("longest volatile (not yet finalized) tail: \(await longestVolatile.value) chars")
        print("outcomes: \(result.outcomes)")
        print("\n\(result.text)")
    }

    static func take(_ flag: String, from args: inout [String]) -> Bool {
        guard let index = args.firstIndex(of: flag) else { return false }
        args.remove(at: index)
        return true
    }

    static func takeValue(_ flag: String, from args: inout [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        args.removeSubrange(index...index + 1)
        return value
    }

    static func usage() {
        print("usage: speak-bench status | transcribe [--realtime] <audio>... | run [--realtime] <audio>... | polish [--style s] <text> | cases <file.json>")
    }
}

/// Logs each model call: when it started, how long it took, and how much text it was given.
final class TimedPolisher: TextPolisher {
    private let base: FoundationModelsPolisher
    private let stamp: @Sendable () -> String

    init(_ base: FoundationModelsPolisher, stamp: @escaping @Sendable () -> String) {
        self.base = base
        self.stamp = stamp
    }

    func availability() -> PolisherAvailability { base.availability() }
    func prewarm(context: PolishContext) { base.prewarm(context: context) }

    func polish(_ raw: String, context: PolishContext) async throws -> String {
        let start = ContinuousClock.now
        print("\(stamp())    model ← \(raw.count) chars")
        defer { print("\(stamp())    model → done in \(ContinuousClock.now - start)") }
        return try await base.polish(raw, context: context)
    }
}
