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

    private(set) var modelState = ModelState.loading
    private(set) var hasAccessibility = false
    private(set) var hasMicrophone = true

    var status: Status {
        if !hasMicrophone { return .needsMicrophone }
        if !hasAccessibility { return .needsAccessibility }
        switch modelState {
        case .loading: return .starting
        case .ready: return .ready
        case .failed(let message): return .failed(message)
        }
    }
    private(set) var isRecording = false
    private(set) var history = History(fileURL: History.defaultURL)
    private(set) var polisherAvailability: PolisherAvailability = .available

    let pill = PillModel()

    @ObservationIgnored private let transcriber = AppleSpeechTranscriber()
    @ObservationIgnored private let polisher = FoundationModelsPolisher()
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private lazy var panel = PillPanel(model: pill)
    @ObservationIgnored private var machine = TriggerStateMachine()
    @ObservationIgnored private var session: (any TranscriptionSession)?
    @ObservationIgnored private var target: (bundleID: String?, name: String?)
    /// Set while a finished dictation is being transcribed/polished/pasted.
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

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
        // One dictation at a time: ignore the key while the previous one is still being processed.
        if isFinishing, !machine.isActive { return }
        for action in machine.handle(event, at: ProcessInfo.processInfo.systemUptime) {
            perform(action)
        }
        hotkeys.swallowsEscape = machine.isActive
    }

    private func perform(_ action: TriggerAction) {
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
            finishRecording()
        case .cancel:
            cancelRecording()
        }
    }

    private func startRecording() {
        // Permission may have been granted in System Settings since launch.
        if !hasMicrophone { hasMicrophone = AVAudioApplication.shared.recordPermission == .granted }
        guard status == .ready else {
            machine.reset()
            showNotice(statusMessage)
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        target = (app?.bundleIdentifier, app?.localizedName)

        do {
            let session = try transcriber.begin(vocabulary: Preferences.dictionaryWords)
            let pill = pill
            try recorder.start(
                deviceUID: UserDefaults.standard.string(forKey: Preferences.microphoneUID),
                sink: session,
                onLevels: { levels in Task { @MainActor in pill.push(levels) } })
            self.session = session
        } catch {
            machine.reset()
            showNotice("Couldn't start microphone")
            return
        }

        isRecording = true
        noticeTask?.cancel()
        pill.resetLevels()
        pill.handsFree = false
        pill.phase = .listening
        showPill()
        playSound("Tink")
        if UserDefaults.standard.bool(forKey: Preferences.polishEnabled) {
            polisher.prewarm(context: polishContext())
        }
    }

    private func cancelRecording() {
        recorder.stop()
        isRecording = false
        let session = session
        self.session = nil
        Task { await session?.cancel() }
        hidePill()
    }

    private func finishRecording() {
        recorder.stop()
        isRecording = false
        guard let session else { return hidePill() }
        self.session = nil
        isFinishing = true
        pill.phase = .processing
        pill.handsFree = false
        playSound("Pop")

        let context = polishContext()
        let appName = target.name
        let polishEnabled = UserDefaults.standard.bool(forKey: Preferences.polishEnabled)
        let pipeline = PolishPipeline(polisher: polishEnabled ? polisher : nil)

        Task {
            defer { isFinishing = false }
            let raw: String
            do {
                raw = try await session.finish()
            } catch {
                showNotice("Couldn't transcribe")
                return
            }
            guard !raw.isEmpty else { return hidePill() }

            let result = await pipeline.run(raw, context: context)
            refreshPolisherAvailability()
            hidePill()
            await inserter.insert(result.text)
            history.add(HistoryItem(raw: raw, text: result.text, appName: appName))
        }
    }

    private func polishContext() -> PolishContext {
        PolishContext(
            appName: target.name,
            style: AppStyle.forBundleID(target.bundleID),
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

    private func showPill() {
        pill.isVisible = true
        panel.show()
    }

    private func hidePill() {
        pill.isVisible = false
        panel.hide()
    }

    private func showNotice(_ message: String) {
        pill.phase = .notice(message)
        showPill()
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hidePill()
        }
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
