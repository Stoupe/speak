import AVFAudio
import Foundation

/// Speech-to-text engine. Implementations must be cheap to `begin` so recording can start instantly.
public protocol Transcriber: Sendable {
    /// Loads models / downloads assets. Call once at launch; safe to call again.
    func prepare() async throws
    /// Starts a new streaming session. Must return immediately; any slow setup happens inside the session.
    func begin(vocabulary: [String]) throws -> any TranscriptionSession
}

public protocol TranscriptionSession: AnyObject, Sendable {
    /// Feeds microphone audio. Called on the audio thread, serially.
    func append(_ buffer: AVAudioPCMBuffer)
    /// Running transcript (finalized + volatile text) as it changes.
    var partials: AsyncStream<String> { get }
    /// Ends input and returns the final transcript.
    func finish() async throws -> String
    /// Ends input and discards everything.
    func cancel() async
}

/// Where the text is going, so the polisher can match tone.
public struct PolishContext: Sendable, Equatable {
    public var appName: String?
    public var style: AppStyle
    public var vocabulary: [String]

    public init(appName: String? = nil, style: AppStyle = .general, vocabulary: [String] = []) {
        self.appName = appName
        self.style = style
        self.vocabulary = vocabulary
    }
}

/// Text cleanup engine (filler words, self-corrections, punctuation, formatting).
public protocol TextPolisher: Sendable {
    /// Whether the engine can run right now, with a human-readable reason if not.
    func availability() -> PolisherAvailability
    /// Hint that a `polish` call is coming soon (e.g. on Fn down).
    func prewarm(context: PolishContext)
    func polish(_ raw: String, context: PolishContext) async throws -> String
}

public enum PolisherAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}
