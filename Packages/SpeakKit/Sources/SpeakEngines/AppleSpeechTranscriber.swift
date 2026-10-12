import AVFAudio
import Foundation
import Speech
import SpeakCore

/// Streaming on-device transcription with Apple's SpeechAnalyzer / SpeechTranscriber.
public final class AppleSpeechTranscriber: Transcriber {
    public enum Failure: Error, CustomStringConvertible {
        case unsupportedLocale(Locale)
        case noAudioFormat

        public var description: String {
            switch self {
            case .unsupportedLocale(let locale): "Speech recognition doesn't support \(locale.identifier)."
            case .noAudioFormat: "Speech recognition has no compatible audio format."
            }
        }
    }

    private struct Prepared: Sendable {
        var locale: Locale
        var format: AVAudioFormat
    }

    private let requestedLocale: Locale
    private let prepared = Locked<Prepared?>(nil)

    public init(locale: Locale = .current) {
        requestedLocale = locale
    }

    public func prepare() async throws {
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        if locale == nil {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        }
        guard let locale else { throw Failure.unsupportedLocale(requestedLocale) }

        let transcriber = Self.makeModule(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noAudioFormat
        }
        prepared.withLock { $0 = Prepared(locale: locale, format: format) }

        // Run a short silent session so the model is loaded before the first real dictation.
        let warmUp = try begin(vocabulary: [])
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 2)) {
            silence.frameLength = silence.frameCapacity
            warmUp.append(silence)
        }
        _ = try? await warmUp.finish()
    }

    public func begin(vocabulary: [String]) throws -> any TranscriptionSession {
        guard let prepared = prepared.withLock({ $0 }) else {
            throw Failure.unsupportedLocale(requestedLocale)
        }
        return AppleTranscriptionSession(
            module: Self.makeModule(locale: prepared.locale),
            format: prepared.format,
            vocabulary: vocabulary)
    }

    static func makeModule(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])
    }
}

/// One dictation. Audio can be appended immediately; the analyzer spins up in the background and the
/// input stream buffers anything that arrives before it's ready.
final class AppleTranscriptionSession: TranscriptionSession, @unchecked Sendable {
    // `@unchecked`: all mutable state lives behind `Locked`; the converter is only used inside its lock.

    let partials: AsyncStream<TranscriptSnapshot>
    let finalized: AsyncStream<String>

    private let analyzer: SpeechAnalyzer
    /// The converter isn't thread-safe and is used from the audio thread and from finish/cancel.
    private let inputState: Locked<InputState>
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let partialsContinuation: AsyncStream<TranscriptSnapshot>.Continuation
    private let finalizedContinuation: AsyncStream<String>.Continuation
    private let startTask: Task<Void, any Error>
    private let resultsTask: Task<Void, any Error>
    private let text = Locked(Transcript())

    struct InputState {
        var converter: AnalyzerInputConverter
        var closed = false
    }

    struct Transcript {
        var finalized = ""
        var volatile = ""
        var combined: String { (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    init(module: SpeechTranscriber, format: AVAudioFormat, vocabulary: [String]) {
        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        self.analyzer = analyzer
        inputState = Locked(InputState(converter: AnalyzerInputConverter(analyzerFormat: format)))

        let (inputStream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.input = input
        (partials, partialsContinuation) = AsyncStream<TranscriptSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        (finalized, finalizedContinuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))

        startTask = Task {
            if !vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocabulary
                try await analyzer.setContext(context)
            }
            try await analyzer.start(inputSequence: inputStream)
        }

        let text = text
        let partialsContinuation = partialsContinuation
        let finalizedContinuation = finalizedContinuation
        resultsTask = Task {
            for try await result in module.results {
                let chunk = String(result.text.characters)
                let snapshot = text.withLock { transcript in
                    if result.isFinal {
                        transcript.finalized += chunk
                        transcript.volatile = ""
                    } else {
                        transcript.volatile = chunk
                    }
                    // Same leading trim as `combined`, so `finish()`'s transcript starts with this text.
                    return TranscriptSnapshot(
                        finalized: String(transcript.finalized.drop(while: \.isWhitespace)),
                        volatile: transcript.volatile)
                }
                partialsContinuation.yield(snapshot)
                if result.isFinal { finalizedContinuation.yield(snapshot.finalized) }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        inputState.withLock { state in
            guard !state.closed else { return }
            // A single bad buffer shouldn't end the dictation, so conversion errors are dropped.
            for item in (try? state.converter.convert(buffer, at: nil)) ?? [] { input.yield(item) }
        }
    }

    func finish() async throws -> String {
        closeInput(flush: true)
        defer {
            partialsContinuation.finish()
            finalizedContinuation.finish()
        }
        try await startTask.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask.value
        return text.withLock { $0.combined }
    }

    func cancel() async {
        closeInput(flush: false)
        partialsContinuation.finish()
        finalizedContinuation.finish()
        startTask.cancel()
        await analyzer.cancelAndFinishNow()
        resultsTask.cancel()
    }

    private func closeInput(flush: Bool) {
        inputState.withLock { state in
            guard !state.closed else { return }
            state.closed = true
            if flush {
                for item in (try? state.converter.flush()) ?? [] { input.yield(item) }
            }
            input.finish()
        }
    }
}

