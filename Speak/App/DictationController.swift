import AppKit
import AVFAudio
import ApplicationServices
import Observation
import SpeakCore
import SpeakEngines

/// Wires Fn key → recording → transcription → polish → paste, and drives the pill and menu.
@MainActor
@Observable
final class DictationController {
    enum Status: Equatable {
        case starting
        case ready
        case needsAccessibility
        case needsMicrophone
        case failed(String)
    }

    enum ModelState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// Longest single dictation; also the safety net if a Fn key-up is ever lost.
    static let maxRecording: Duration = .seconds(300)
    /// Keep the mic open briefly after release: people let go of Fn on the last syllable.
    static let tailCapture: Duration = .milliseconds(200)

    private(set) var modelState = ModelState.loading
    private(set) var hasAccessibility = false
    private(set) var hasMicrophone = true
    private(set) var isRecording = false
    private(set) var history = History(fileURL: History.defaultURL)
    private(set) var polisherAvailability: PolisherAvailability = .available

    var status: Status {
        if !hasMicrophone { return .needsMicrophone }
        if !hasAccessibility { return .needsAccessibility }
        switch modelState {
        case .loading: return .starting
        case .ready: return .ready
        case .failed(let message): return .failed(message)
        }
    }

    let pill = PillModel()

    @ObservationIgnored private let transcriber = AppleSpeechTranscriber()
    @ObservationIgnored private let polisher = FoundationModelsPolisher()
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private lazy var panel = PillPanel(model: pill)
    @ObservationIgnored private var machine = TriggerStateMachine()
    @ObservationIgnored private var current: Recording?
    /// Dictations released but not yet pasted. A new one can start while these finish.
    @ObservationIgnored private var finishingCount = 0
    /// The most recent finishing dictation; each waits for the previous so pastes keep spoken order.
    @ObservationIgnored private var lastFinish: Task<Void, Never>?
    /// A short message for the pill. Its countdown starts only once it's actually on screen, so a failure
    /// that happens while you're recording the next dictation is still shown afterwards.
    @ObservationIgnored private var notice: (message: String, dismissal: Task<Void, Never>?)?

    private struct Recording {
        var session: any TranscriptionSession
        var recorderID: Int
        var appPID: pid_t?
        var appBundleID: String?
        var appName: String?
        var startedAt: ContinuousClock.Instant
        var timeLimit: Task<Void, Never>
    }

    init() {
        pill.onCancel = { [weak self] in self?.handle(.escape) }
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
    }

    func launch() {
        Task {
            await requestMicrophone()
            startHotkeys()
            do {
                try await transcriber.prepare()
                modelState = .ready
            } catch {
                modelState = .failed("Speech model unavailable: \(error)")
            }
        }
        refreshPolisherAvailability()
    }

    // MARK: Permissions

    private func requestMicrophone() async {
        hasMicrophone = await AVAudioApplication.requestRecordPermission()
    }

    /// Installs the Fn tap, prompting for Accessibility and polling until it's granted.
    private func startHotkeys() {
        // Fn arrives as a modifier change with Accessibility alone; Escape and other keys (used to cancel)
        // are only delivered to the tap with Input Monitoring.
        let canListen = CGPreflightListenEventAccess()
        log.info("input monitoring: \(canListen), accessibility: \(AXIsProcessTrusted())")
        if !canListen { CGRequestListenEventAccess() }
        if hotkeys.start() {
            hasAccessibility = true
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        Task {
            while !hotkeys.start() {
                try? await Task.sleep(for: .seconds(2))
            }
            hasAccessibility = true
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    func refreshPolisherAvailability() {
        polisherAvailability = polisher.availability()
    }

    // MARK: Trigger handling

    private func handle(_ event: TriggerEvent) {
        log.debug("event \(String(describing: event), privacy: .public) in state \(String(describing: self.machine.state), privacy: .public)")
        for action in machine.handle(event, at: ProcessInfo.processInfo.systemUptime) {
            perform(action)
        }
        hotkeys.swallowsEscape = machine.isActive
    }

    private func perform(_ action: TriggerAction) {
        log.info("action \(String(describing: action), privacy: .public)")
        switch action {
        case .startRecording:
            startRecording()
        case .enterHandsFree:
            pill.handsFree = true
        case .scheduleTapWindow(let id, let seconds):
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                handle(.tapWindowElapsed(id: id))
            }
        case .commit:
            commitRecording()
        case .cancel:
            cancelRecording()
        }
    }

    private func startRecording() {
        // Permission may have been granted in System Settings since launch.
        if !hasMicrophone { hasMicrophone = AVAudioApplication.shared.recordPermission == .granted }
        guard status == .ready else {
            log.error("not ready: \(self.statusMessage, privacy: .public)")
            machine.reset()
            showNotice(statusMessage)
            return
        }

        let session: any TranscriptionSession
        let recorderID: Int
        do {
            session = try transcriber.begin(vocabulary: Preferences.dictionaryWords)
        } catch {
            machine.reset()
            showNotice("Speech model isn't ready")
            return
        }
        do {
            let pill = pill
            recorderID = try recorder.start(
                deviceUID: UserDefaults.standard.string(forKey: Preferences.microphoneUID),
                sink: session,
                onLevels: { levels in Task { @MainActor in pill.push(levels) } })
        } catch {
            Task { await session.cancel() }
            machine.reset()
            showNotice("Couldn't start microphone")
            return
        }

        let app = NSWorkspace.shared.frontmostApplication
        current = Recording(
            session: session,
            recorderID: recorderID,
            appPID: app?.processIdentifier,
            appBundleID: app?.bundleIdentifier,
            appName: app?.localizedName,
            startedAt: .now,
            timeLimit: Task {
                try? await Task.sleep(for: Self.maxRecording)
                guard !Task.isCancelled else { return }
                handle(.timeLimitReached)
            })

        isRecording = true
        pill.resetLevels()
        pill.handsFree = false
        updatePill()
        playSound("Tink")
        if UserDefaults.standard.bool(forKey: Preferences.polishEnabled) {
            polisher.prewarm(context: polishContext(for: current!))
        }
    }

    private func cancelRecording() {
        guard let recording = endRecording() else { return }
        recorder.stop(recording.recorderID)
        Task { await recording.session.cancel() }
        updatePill()
    }

    private func commitRecording() {
        guard let recording = endRecording() else { return }
        playSound("Pop")

        let context = polishContext(for: recording)
        let polishEnabled = UserDefaults.standard.bool(forKey: Preferences.polishEnabled)
        let pipeline = PolishPipeline(polisher: polishEnabled ? polisher : nil)
        // Generous: finishing normally takes well under a second, but long dictations have more to finalize.
        let finishTimeout = Duration.seconds(5) + (ContinuousClock.now - recording.startedAt) / 10
        let previous = lastFinish

        finishingCount += 1
        updatePill()

        lastFinish = Task {
            defer {
                finishingCount -= 1
                updatePill()
            }
            try? await Task.sleep(for: Self.tailCapture)
            recorder.stop(recording.recorderID)

            let session = recording.session
            let raw: String
            switch await withTimeout(finishTimeout, operation: { try await session.finish() }) {
            case .some(.success(let text)):
                raw = text
            case .some(.failure(let error)):
                log.error("transcription failed: \(String(describing: error), privacy: .public)")
                return showNotice("Couldn't transcribe")
            case .none:
                Task { await session.cancel() }
                return showNotice("Transcription timed out")
            }
            log.info("raw transcript (\(raw.count) chars): \(raw, privacy: .private)")
            guard !raw.isEmpty else { return }

            let result = await pipeline.run(raw, context: context)
            refreshPolisherAvailability()
            log.info("polish \(String(describing: result.outcome), privacy: .public) in \(result.duration, privacy: .public): \(result.text, privacy: .private)")

            // Paste in the order dictations were spoken.
            await previous?.value
            history.add(HistoryItem(raw: raw, text: result.text, appName: recording.appName))

            // Don't paste into a different app than the one you were dictating into.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == recording.appPID else {
                log.info("frontmost app changed; copying instead of pasting")
                inserter.copy(result.text)
                return showNotice("App changed — copied instead")
            }
            let text = FocusedText.withLeadingSpaceIfNeeded(result.text, after: FocusedText.characterBeforeCaret())
            await inserter.insert(text)
        }
    }

    /// Clears the current recording and its timer; the caller stops the mic and session.
    private func endRecording() -> Recording? {
        guard let recording = current else { return nil }
        recording.timeLimit.cancel()
        current = nil
        isRecording = false
        pill.handsFree = false
        return recording
    }

    private func polishContext(for recording: Recording) -> PolishContext {
        PolishContext(
            appName: recording.appName,
            style: AppStyle.forBundleID(recording.appBundleID),
            vocabulary: Preferences.dictionaryWords)
    }

    // MARK: History

    func copy(_ item: HistoryItem) {
        inserter.copy(item.text)
    }

    func pasteLast() {
        guard let last = history.items.first else { return }
        Task { await inserter.insert(last.text) }
    }

    func clearHistory() {
        history.clear()
    }

    // MARK: Pill

    /// Single source of truth for what the pill shows: recording beats processing beats a notice.
    private func updatePill() {
        defer { log.debug("pill visible=\(self.pill.isVisible) phase=\(String(describing: self.pill.phase), privacy: .public) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)") }
        if isRecording {
            pill.phase = .listening
        } else if finishingCount > 0 {
            pill.phase = .processing
        } else if let notice {
            pill.phase = .notice(notice.message)
            if notice.dismissal == nil {
                self.notice?.dismissal = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self.notice = nil
                    updatePill()
                }
            }
        } else {
            pill.isVisible = false
            panel.hide()
            return
        }
        pill.isVisible = true
        panel.show()
    }

    private func showNotice(_ message: String) {
        notice?.dismissal?.cancel()
        notice = (message, nil)
        updatePill()
    }

    var statusMessage: String {
        switch status {
        case .starting: "Loading speech model…"
        case .ready: "Hold fn to dictate"
        case .needsAccessibility: "Needs Accessibility access"
        case .needsMicrophone: "Needs microphone access"
        case .failed(let message): message
        }
    }

    private func playSound(_ name: String) {
        guard UserDefaults.standard.bool(forKey: Preferences.soundsEnabled),
              let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
        else { return }
        sound.volume = 0.25
        sound.play()
    }
}
