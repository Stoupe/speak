import Foundation

/// Runs a polisher with guard rails. Never throws: worst case you get the raw transcript back.
public struct PolishPipeline: Sendable {
    public enum Outcome: Equatable, Sendable {
        case polished
        case skippedShort
        case disabled
        case unavailable(String)
        case timedOut
        case failed(String)
        case rejected(PolishGuard.Rejection)
    }

    public struct Result: Equatable, Sendable {
        public var text: String
        public var outcome: Outcome
        public var duration: Duration
    }

    public var polisher: (any TextPolisher)?
    /// Time allowed for any polish…
    public var timeout: Duration
    /// …plus this much per character of transcript (longer text takes longer to generate)…
    public var timeoutPerCharacter: Duration
    /// …up to this ceiling.
    public var maxTimeout: Duration

    /// The defaults leave room for a slow call on an 8 GB M1 (1–4 s for a couple of sentences): a timeout means
    /// waiting the full limit and then getting raw text, the worst of both.
    public init(
        polisher: (any TextPolisher)?,
        timeout: Duration = .seconds(3),
        timeoutPerCharacter: Duration = .milliseconds(15),
        maxTimeout: Duration = .seconds(8)
    ) {
        self.polisher = polisher
        self.timeout = timeout
        self.timeoutPerCharacter = timeoutPerCharacter
        self.maxTimeout = maxTimeout
    }

    /// The same pipeline with every time limit multiplied by `factor`.
    public func withTimeoutsScaled(by factor: Int) -> PolishPipeline {
        PolishPipeline(
            polisher: polisher,
            timeout: timeout * factor,
            timeoutPerCharacter: timeoutPerCharacter * factor,
            maxTimeout: maxTimeout * factor)
    }

    func timeout(for raw: String) -> Duration {
        min(timeout + timeoutPerCharacter * raw.count, maxTimeout)
    }

    public func run(_ raw: String, context: PolishContext) async -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func done(_ text: String, _ outcome: Outcome) -> Result {
            Result(text: text, outcome: outcome, duration: clock.now - start)
        }

        guard let polisher else { return done(raw, .disabled) }
        if raw.isEmpty || PolishGuard.shouldSkip(raw) { return done(raw, .skippedShort) }
        if case .unavailable(let reason) = polisher.availability() { return done(raw, .unavailable(reason)) }

        let attempt = await withTimeout(timeout(for: raw)) { try await polisher.polish(raw, context: context) }
        switch attempt {
        case .none:
            return done(raw, .timedOut)
        case .some(.failure(let error)):
            return done(raw, .failed(String(describing: error)))
        case .some(.success(let polished)):
            if let rejection = PolishGuard.rejection(raw: raw, polished: polished) {
                return done(raw, .rejected(rejection))
            }
            return done(polished.trimmingCharacters(in: .whitespacesAndNewlines), .polished)
        }
    }
}

/// Returns the operation's result, or nil if it didn't finish within `timeout`.
/// Unlike a task group, this returns as soon as the deadline passes even if the operation ignores cancellation.
public func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async -> Swift.Result<T, any Error>? {
    let box = OneShot<Swift.Result<T, any Error>?>()
    return await withCheckedContinuation { continuation in
        box.install(continuation)
        let work = Task {
            do { box.resume(.success(try await operation())) } catch { box.resume(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: timeout)
            if box.resume(nil) { work.cancel() }
        }
    }
}

/// Resumes a continuation exactly once, from whichever side gets there first.
private final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var pending: T??

    func install(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if let value = pending {
            lock.unlock()
            continuation.resume(returning: value!)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Returns true if this call won.
    @discardableResult
    func resume(_ value: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let continuation {
            self.continuation = nil
            pending = .some(value)
            continuation.resume(returning: value)
            return true
        }
        if pending == nil {
            pending = .some(value)
            return true
        }
        return false
    }
}
