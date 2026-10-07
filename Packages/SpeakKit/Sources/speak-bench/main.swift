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
        let pipeline = PolishPipeline(polisher: FoundationModelsPolisher(), timeout: .seconds(10))
        var exact = 0
        var total = Duration.zero
        for (index, item) in cases.enumerated() {
            var context = context
            if let style = item.style.flatMap(AppStyle.init(rawValue:)) { context.style = style }
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
