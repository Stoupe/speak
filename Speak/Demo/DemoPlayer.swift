#if DEBUG
import AppKit
import SpeakCore

/// Plays a `DemoScene`: puts its backdrop on screen with the pill in place, waits for `Tools/demo.sh` to start it,
/// then runs the steps on the real pill.
///
/// The pill changes mirror `DictationController` (`startRecording`, `commitRecording`, `updatePill`); keep them in
/// step when that choreography changes.
@MainActor
final class DemoPlayer {
    private let scene: DemoScene
    private let pill: PillModel
    private let panel: PillPanel
    private let document = DemoDocument()
    private var backdrop: NSWindow?

    // The dictation so far, in the recognizer's terms: finalized text, where each finalized passage ends (oldest
    // first, not yet cleaned up), and words still arriving.
    private var finalized = ""
    private var passageEnds: [Int] = []
    private var volatile = ""
    private var polished = ""
    private var polishedThrough = 0
    private var polishes: [Task<Void, Never>] = []
    private var speaking = false

    init(scene: DemoScene, pill: PillModel, panel: PillPanel) {
        self.scene = scene
        self.pill = pill
        self.panel = panel
    }

    func start() {
        // The display with the menu bar (`NSScreen.main` is wherever the active window is).
        guard let mainDisplay = NSScreen.screens.first else { return }
        let frame = scene.frame(on: mainDisplay)
        backdrop = DemoBackdrop.show(scene.backdrop, document: document, frame: frame)
        panel.demoAnchor = NSPoint(x: frame.midX, y: frame.minY + scene.pillHeight)
        DemoCapture.announce(scene.capture, region: frame)

        Task { await animateLevels() }
        Task {
            await DemoCapture.waitForStart()
            await run()
            DemoCapture.finished()
            if scene.capture == .menu { await DemoCapture.reportMenu() }
        }
    }

    private func run() async {
        for step in scene.steps {
            switch step {
            case .wait(let seconds):
                await delay(seconds)
            case .keyDown(let handsFree):
                finalized = ""; passageEnds = []; volatile = ""; polished = ""; polishedThrough = 0
                updateCard()
                pill.phase = .listening
                pill.handsFree = handsFree
                pill.micLive = false
                pill.isVisible = true
                panel.show()
                await delay(0.3)
                pill.micLive = true
            case .say(let text, let wordsPerSecond):
                speaking = true
                for word in text.split(separator: " ") {
                    volatile += volatile.isEmpty && finalized.isEmpty ? word : " " + word
                    updateCard()
                    await delay(1 / wordsPerSecond)
                }
                speaking = false
                finalized += volatile
                passageEnds.append(finalized.count)
                volatile = ""
                updateCard()
            case .polish(let text, let after):
                polishes.append(Task {
                    await delay(after)
                    guard !passageEnds.isEmpty else { return }
                    polishedThrough = passageEnds.removeFirst()
                    polished += polished.isEmpty ? text : " " + text
                    updateCard()
                })
            case .release(let processing):
                let started = ContinuousClock.now
                pill.phase = .processing
                pill.handsFree = false
                for polish in polishes { await polish.value }
                polishes = []
                // Leave the final text readable for a moment before the card folds away.
                let elapsed = (ContinuousClock.now - started) / .seconds(1)
                await delay(max(processing - elapsed, 0.5))
                pill.showsCard = false
                pill.isVisible = false
                panel.hide()
                document.paste(polished)
            case .card(let live, let handsFree):
                speaking = true
                pill.handsFree = handsFree
                pill.micLive = true
                pill.phase = .listening
                pill.live = live
                pill.showsCard = true
                pill.isVisible = true
                panel.show()
            case .submit:
                document.submit()
            }
        }
    }

    private func updateCard() {
        pill.live = LiveTranscript.compose(
            snapshot: TranscriptSnapshot(finalized: finalized, volatile: volatile),
            polished: polished, polishedThrough: polishedThrough)
        if !pill.live.isEmpty { pill.showsCard = true }
    }

    /// Loud and uneven while words arrive, near silent otherwise.
    private func animateLevels() async {
        var t = 0.0
        while true {
            t += 0.05
            let level = speaking
                ? 0.1 + 0.5 * abs(sin(t * 3.1)) * abs(sin(t * 1.3 + 1)) + .random(in: 0...0.2)
                : .random(in: 0...0.04)
            pill.push([Float(level)])
            await delay(0.05)
        }
    }
}
#endif
