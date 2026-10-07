import AVFAudio
import AudioToolbox
import SpeakCore

/// Captures microphone audio and hands it straight to a transcription session.
@MainActor
final class AudioRecorder {
    enum Failure: Error, CustomStringConvertible {
        case noInputDevice

        var description: String { "No microphone available" }
    }

    /// A fresh engine per recording picks up device changes (AirPods connecting, etc.) without bookkeeping.
    private var engine: AVAudioEngine?
    private var recordingID = 0

    /// - Parameters:
    ///   - deviceUID: Core Audio device UID, or nil for the system default input.
    ///   - onLevels: Normalized (0…1) loudness, several values per audio buffer. Called on the audio thread.
    /// - Returns: An ID to pass to `stop(_:)`.
    @discardableResult
    func start(
        deviceUID: String?,
        sink: any TranscriptionSession,
        onLevels: @escaping @Sendable ([Float]) -> Void
    ) throws -> Int {
        stopCurrent()
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
        try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
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
        recordingID += 1
        return recordingID
    }

    /// Stops the recording with this ID, if it's still the current one.
    func stop(_ id: Int) {
        guard id == recordingID else { return }
        stopCurrent()
    }

    private func stopCurrent() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Splits the buffer into ~20 ms windows and returns each window's loudness mapped from -50…-10 dBFS to 0…1.
    private nonisolated static func levels(of buffer: AVReadOnlyAudioPCMBuffer) -> [Float] {
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
