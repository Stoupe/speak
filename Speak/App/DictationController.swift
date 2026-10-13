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
    @ObservationIgnored private let setupWindow = SetupWindowController()
    @ObservationIgnored private var machine = TriggerStateMachine()
    @ObservationIgnored private var current: Recording?
    /// Dictations released but not yet pasted. A new one can start while these finish.
    @ObservationIgnored private var finishingCount = 0
    /// The most recent finishing dictation; each waits for the previous so pastes keep spoken order.
    @ObservationIgnored private var lastFinish: Task<Void, Never>?
    /// A short message for the pill. Its countdown starts only once it's actually on screen, so a failure
    /// that happens while you're recording the next dictation is still shown afterwards.
    @ObservationIgnored private var notice: (message: String, dismissal: Task<Void, Never>?)?
    /// What the pill's text card is made of, and which dictation it belongs to (nil once it has closed).
    @ObservationIgnored private var live = LiveState()

    private struct LiveState {
        var recorderID: Int?
        var snapshot = TranscriptSnapshot()
        var progress = IncrementalPolish.Progress()
    }

    private struct Recording {
        var session: any TranscriptionSession
        var recorderID: Int
        var appPID: pid_t?
        var appBundleID: String?
        var appName: String?
        var startedAt: ContinuousClock.Instant
        var timeLimit: Task<Void, Never>
        /// Polishes finished sentences while the user is still talking.
        var incremental: IncrementalPolish
        /// Feeds finalized transcript text into `incremental`; ends when the session finishes.
        var feed: Task<Void, Never>
        /// Follow the recognized and the polished text for the pill's card; end when the dictation does.
        var liveWords: Task<Void, Never>
        var livePolish: Task<Void, Never>
    }

    init() {
        pill.onCancel = { [weak self] in self?.handle(.escape) }
        hotkeys.onEvent = { [weak self] event, time in self?.handle(event, at: time) }
        hotkeys.onClick = { [weak self] location, time in
            guard let self else { return }
            // Clicking or dragging the pill itself isn't "another key"; any other click cancels a held dictation.
            guard !panel.showsPill(atGlobal: location) else { return }
            handle(.otherKey, at: time)
        }
    }

    func launch() {
        recorder.warmUp()
        _ = panel // Build the pill's window now so the first key press doesn't pay for it.
        refreshPermissions()
        startHotkeys()
        Task {
            do {
                try await transcriber.prepare()
                modelState = .ready
            } catch {
                modelState = .failed("Speech model unavailable: \(error)")
            }
        }
        refreshPolisherAvailability()
        // Load the language model now so the first dictation doesn't pay for it.
        if polisherAvailability == .available {
            polisher.prewarm(context: PolishContext())
        }
        // Permissions are requested from the setup window (with an explanation), not with bare system prompts.
        // After the first run, only reappear if something Speak can't work without is missing.
        let status = SetupStatus()
        if !UserDefaults.standard.bool(forKey: Preferences.setupCompleted)
            || status.microphone != .granted || !status.accessibility {
            showSetup()
        }
    }

    // MARK: Permissions

    func showSetup() {
        setupWindow.show(controller: self)
    }

    func refreshPermissions() {
        hasMicrophone = AVAudioApplication.shared.recordPermission == .granted
        hasAccessibility = AXIsProcessTrusted() && hotkeys.isRunning
    }

    /// Installs the key tap, polling until Accessibility has been granted.
    private func startHotkeys() {
        Task {
            while !hotkeys.start() {
                try? await Task.sleep(for: .seconds(1))
            }
            // Modifier keys arrive with Accessibility alone; other keys (used to cancel) may also need
            // Input Monitoring, which macOS has granted alongside so far. Log it so it's diagnosable.
            log.info("input monitoring: \(CGPreflightListenEventAccess())")
            hasAccessibility = true
        }
    }

    func refreshPolisherAvailability() {
        polisherAvailability = polisher.availability()
    }

    // MARK: Trigger handling

    private func handle(_ event: TriggerEvent, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if event != .otherKey || machine.isActive {
            log.debug("event \(String(describing: event), privacy: .public) in state \(String(describing: self.machine.state), privacy: .public)")
        }
        for action in machine.handle(event, at: time) {
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
            updatePill()
        case .scheduleTapWindow(let id, let seconds):
            // The pill hides until we know whether this short tap is the start of a double-tap.
            updatePill()
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
        let keyDown = ContinuousClock.now
        // Permission may have been granted in System Settings since launch.
        refreshPermissions()
        guard status == .ready else {
            log.error("not ready: \(self.statusMessage, privacy: .public)")
            machine.reset()
            showNotice(statusMessage)
            return
        }

        let session: any TranscriptionSession
        do {
            session = try transcriber.begin(vocabulary: Preferences.dictionaryWords)
        } catch {
            machine.reset()
            showNotice("Speech model isn't ready")
            return
        }
        let pill = pill
        let recorderID = recorder.start(
            deviceUID: UserDefaults.standard.string(forKey: Preferences.microphoneUID),
            sink: session,
            onLevels: { levels in Task { @MainActor in pill.push(levels) } },
            onEvent: { [weak self] id, event in
                Task { @MainActor in self?.micEvent(event, recorderID: id, keyDown: keyDown) }
            })

        let app = NSWorkspace.shared.frontmostApplication
        let context = PolishContext(
            appName: app?.localizedName,
            style: AppStyle.forBundleID(app?.bundleIdentifier),
            vocabulary: Preferences.dictionaryWords)
        let polishEnabled = UserDefaults.standard.bool(forKey: Preferences.polishEnabled)
        let incremental = IncrementalPolish(pipeline: PolishPipeline(polisher: polishEnabled ? polisher : nil), context: context)
        let finalizedText = session.finalized
        let partials = session.partials
        let progress = incremental.progress
        live = LiveState(recorderID: recorderID)
        pill.live = LiveTranscript()
        pill.showsCard = false
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
            },
            incremental: incremental,
            feed: Task {
                for await text in finalizedText { await incremental.update(finalized: text) }
            },
            liveWords: Task {
                for await snapshot in partials { showLive(recorderID) { $0.snapshot = snapshot } }
            },
            livePolish: Task {
                for await polished in progress { showLive(recorderID) { $0.progress = polished } }
            })

        isRecording = true
        pill.resetLevels()
        pill.handsFree = false
        pill.micLive = false
        // On screen straight away, red until the mic is live (see `micEvent`).
        updatePill()
        if polishEnabled { polisher.prewarm(context: context) }
    }

    /// The mic is capturing (or couldn't start). Only now does the waveform light up and Tink say "go ahead".
    private func micEvent(_ event: AudioRecorder.Event, recorderID: Int, keyDown: ContinuousClock.Instant) {
        guard current?.recorderID == recorderID else { return }
        switch event {
        case .live:
            log.info("mic live \(ContinuousClock.now - keyDown, privacy: .public) after key down")
            pill.micLive = true
            playSound("Tink")
        case .failed(let error):
            log.error("mic failed: \(String(describing: error), privacy: .public)")
            cancelRecording()
            machine.reset()
            hotkeys.swallowsEscape = false
            showNotice("Couldn't start microphone")
        }
    }

    private func cancelRecording() {
        guard let recording = endRecording() else { return }
        recorder.stop(recording.recorderID)
        recording.feed.cancel()
        recording.liveWords.cancel()
        recording.livePolish.cancel()
        closeCard(recording.recorderID)
        Task {
            await recording.session.cancel()
            await recording.incremental.cancel()
        }
        updatePill()
    }

    private func commitRecording() {
        guard let recording = endRecording() else { return }
        playSound("Pop")
        // Whatever is still to come gets polished in one go once the transcript is final.
        Task { await recording.incremental.endOfSpeech() }

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
                closeCard(recording.recorderID)
                await recording.incremental.cancel()
                return showNotice("Couldn't transcribe")
            case .none:
                closeCard(recording.recorderID)
                recording.feed.cancel()
                Task {
                    await session.cancel()
                    await recording.incremental.cancel()
                }
                return showNotice("Transcription timed out")
            }
            // The finalized stream has ended; make sure its last update reached the polisher before finishing.
            await recording.feed.value
            log.info("raw transcript (\(raw.count) chars): \(raw, privacy: .private)")
            guard !raw.isEmpty else {
                closeCard(recording.recorderID)
                await recording.incremental.cancel()
                return
            }

            let polishStart = ContinuousClock.now
            let result = await recording.incremental.finish(transcript: raw)
            refreshPolisherAvailability()
            log.info("polish \(String(describing: result.outcomes), privacy: .public); waited \(ContinuousClock.now - polishStart, privacy: .public) after release: \(result.text, privacy: .private)")
            showLive(recording.recorderID) { live in
                live.snapshot = TranscriptSnapshot(finalized: raw)
                live.progress = IncrementalPolish.Progress(polished: result.text, rawThrough: raw.count)
            }

            // Paste in the order dictations were spoken.
            await previous?.value
            history.add(HistoryItem(raw: raw, text: result.text, appName: recording.appName))
            // The card folds back into the pill as the text lands.
            closeCard(recording.recorderID)

            // Don't paste into a different app than the one you were dictating into.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == recording.appPID else {
                log.info("frontmost app changed; copying instead of pasting")
                inserter.copy(result.text)
                return showNotice("App changed — copied instead")
            }
            await inserter.insert(withTrailingSpace(result.text))
        }
    }

    /// Appends a space (if enabled) so the next dictation doesn't run into this one. Only for pastes:
    /// history and copies keep the text as is.
    private func withTrailingSpace(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: Preferences.trailingSpace),
              let last = text.last, !last.isWhitespace
        else { return text }
        return text + " "
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

    // MARK: Live text

    /// Updates the pill's text card, if it's still showing this dictation. The card opens with the first words.
    private func showLive(_ recorderID: Int, _ update: (inout LiveState) -> Void) {
        guard live.recorderID == recorderID else { return }
        update(&live)
        pill.live = LiveTranscript.compose(
            snapshot: live.snapshot, polished: live.progress.polished, polishedThrough: live.progress.rawThrough)
        if !pill.live.isEmpty, !pill.showsCard {
            pill.showsCard = true
            log.info("card opened (hands-free: \(self.pill.handsFree), pill visible: \(self.pill.isVisible))")
        }
    }

    private func closeCard(_ recorderID: Int) {
        guard live.recorderID == recorderID else { return }
        live.recorderID = nil
        if pill.showsCard { log.info("card closed") }
        pill.showsCard = false
    }

    // MARK: History

    func copy(_ text: String) {
        inserter.copy(text)
    }

    func clearHistory() {
        history.clear()
    }

    // MARK: Pill

    /// Single source of truth for what the pill shows: recording beats processing beats a notice.
    private func updatePill() {
        defer { log.debug("pill visible=\(self.pill.isVisible) phase=\(String(describing: self.pill.phase), privacy: .public) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)") }
        if isRecording, !isAwaitingSecondTap {
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

    private var isAwaitingSecondTap: Bool {
        if case .awaitingSecondTap = machine.state { true } else { false }
    }

    private func showNotice(_ message: String) {
        notice?.dismissal?.cancel()
        notice = (message, nil)
        updatePill()
    }

    var statusMessage: String {
        switch status {
        case .starting: "Loading speech model…"
        case .ready: "Hold \(TriggerKey.current.name) to dictate"
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
