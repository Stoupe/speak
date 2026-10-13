import AVFAudio
import AudioToolbox
import SpeakCore

/// Captures microphone audio and hands it straight to a transcription session.
///
/// Starting the audio engine takes a moment (longer with Bluetooth mics), so it happens on a queue of its own:
/// the main thread is free to show the pill the instant the key goes down, and `.live` says when audio is
/// actually flowing.
@MainActor
final class AudioRecorder {
    enum Failure: Error, CustomStringConvertible {
        case noInputDevice

        var description: String { "No microphone available" }
    }

    enum Event: Sendable {
        /// The first audio has arrived: from here on, speech is captured.
        case live
        case failed(any Error)
    }

    private let queue = DispatchQueue(label: "dev.stoupe.Speak.audio", qos: .userInteractive)
    private let capture = Capture()
    private var recordingID = 0

    /// Starts capturing in the background and returns straight away.
    /// - Parameters:
    ///   - deviceUID: Core Audio device UID, or nil for the system default input.
    ///   - onLevels: Normalized (0…1) loudness, several values per audio buffer. Called on the audio thread.
    ///   - onEvent: Called once, off the main thread, with the recording's ID.
    /// - Returns: An ID to pass to `stop(_:)`.
    @discardableResult
    func start(
        deviceUID: String?,
        sink: any TranscriptionSession,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onEvent: @escaping @Sendable (_ id: Int, Event) -> Void
    ) -> Int {
        recordingID += 1
        let id = recordingID
        let capture = capture
        queue.async {
            do {
                try capture.start(deviceUID: deviceUID, sink: sink, onLevels: onLevels) { onEvent(id, .live) }
            } catch {
                onEvent(id, .failed(error))
            }
        }
        return id
    }

    /// Touches the audio input once at launch so the first real recording doesn't pay Core Audio's cold start.
    /// Doesn't start the engine, so the mic indicator stays off.
    func warmUp() {
        queue.async {
            let engine = AVAudioEngine()
            withExtendedLifetime(engine) { _ = engine.inputNode.outputFormat(forBus: 0) }
        }
    }

    /// Stops the recording with this ID, if it's still the current one.
    func stop(_ id: Int) {
        guard id == recordingID else { return }
        let capture = capture
        queue.async { capture.stop() }
    }
}

/// The engine itself. `@unchecked`: only ever used on `AudioRecorder`'s queue, which keeps start and stop in order.
private final class Capture: @unchecked Sendable {
    /// A fresh engine per recording picks up device changes (AirPods connecting, etc.) without bookkeeping.
    private var engine: AVAudioEngine?

    func start(
        deviceUID: String?,
        sink: any TranscriptionSession,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onLive: @escaping @Sendable () -> Void
    ) throws {
        stop()
        let startedAt = ContinuousClock.now
        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let deviceUID, var deviceID = AudioDevices.deviceID(forUID: deviceUID) {
            input.withAudioUnit { unit in
                guard let unit = copy unit else { return }
                AudioUnitSetProperty(
                    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noInputDevice }

        log.info("mic format: \(format, privacy: .public)")
        let firstBuffer = FirstBuffer()
        try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if !firstBuffer.seen {
                firstBuffer.seen = true
                onLive()
            }
            onLevels(Self.levels(of: buffer))
            sink.append(AVAudioPCMBuffer(copying: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        log.info("mic engine started in \(ContinuousClock.now - startedAt, privacy: .public)")
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private typealias Failure = AudioRecorder.Failure

    /// `@unchecked`: only touched from the tap block, which the engine calls on one thread at a time.
    private final class FirstBuffer: @unchecked Sendable {
        var seen = false
    }

    /// Splits the buffer into ~20 ms windows and returns each window's loudness mapped from -50…-10 dBFS to 0…1.
    private static func levels(of buffer: AVReadOnlyAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0, case .float(let samples) = buffer.channelData(0) else { return [] }
        let frames = min(buffer.frameLength, samples.count)
        let window = max(1, Int(buffer.format.sampleRate / 50))
        return stride(from: 0, to: frames, by: window).map { start in
            let end = min(start + window, frames)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            let db = 20 * log10(max(rms, 1e-6))
            return min(max((db + 50) / 40, 0), 1)
        }
    }
}
