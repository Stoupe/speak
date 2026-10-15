#if DEBUG
import AppKit
import SpeakCore

/// A scripted scene for README screenshots and recordings. `Tools/demo.sh <name>` launches the Debug build with
/// `-demo <name>` and captures it. Instead of the real app (no mic, hotkeys, setup window or history file), the
/// scene puts a mock backdrop on screen with the pill in place, then plays its steps. To make a new one, add it
/// to `all`.
struct DemoScene {
    enum Capture: String {
        /// A PNG of the backdrop area once the steps have run.
        case still
        /// A recording of the backdrop area while the steps run (GIF + MP4).
        case video
        /// A PNG of the menu bar menu, opened by the script once the steps have run.
        case menu
    }

    enum Placement {
        /// Bottom centre of the screen, where the pill sits by default.
        case bottom
        /// Under the menu bar on the right, where the menu opens.
        case topRight
    }

    var capture: Capture
    var backdrop: DemoBackdrop.Kind
    var size: CGSize
    var placement = Placement.bottom
    /// Height of the pill's centre above the backdrop's bottom edge.
    var pillHeight: CGFloat = 44
    /// Recent dictations for the menu, newest first.
    var history: [String] = []
    var steps: [DemoStep] = []

    /// The scene named after `-demo` in the launch arguments, if any.
    static var requested: DemoScene? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo") else { return nil }
        let name = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        guard let scene = all[name] else {
            // Quit quietly (no crash report); `Tools/demo.sh` notices the missing `info` file.
            print("Unknown demo scene '\(name)'. Scenes: \(all.keys.sorted().joined(separator: ", "))")
            exit(1)
        }
        return scene
    }

    static let all: [String: DemoScene] = [
        // The card mid-dictation over an email draft.
        "card": DemoScene(
            capture: .still, backdrop: .mail, size: CGSize(width: 800, height: 440), pillHeight: 130,
            steps: [.card(
                LiveTranscript(
                    polished: "Hey Sam, quick update on the launch: we're on track for Friday. I'll send the notes after lunch.",
                    pending: " Let me know if anything's",
                    volatile: " blocking you"),
                handsFree: true)]),

        // The menu bar menu with recent dictations.
        "menu": DemoScene(
            capture: .menu, backdrop: .plain, size: CGSize(width: 1000, height: 480), placement: .topRight,
            history: [
                "Hey Sam, quick update on the launch: we're on track for Friday.",
                "Thanks! That fixed it.",
                "Remember to book the venue for the 14th.",
                "Can you send me the slides from this morning? I'd like to go over them before the review.",
                "Sounds good, see you at 3.",
            ]),

        // Dictating a prompt into Claude Code in a terminal: a correction gets cleaned up, then it's sent.
        "terminal": DemoScene(
            capture: .video, backdrop: .terminal, size: CGSize(width: 860, height: 540),
            steps: [
                .wait(1.2),
                .keyDown(),
                .say("add a dark mode toggle to the settings page um no wait the appearance page"),
                .polish("Add a dark mode toggle to the appearance page."),
                .wait(0.3),
                .say("and make it follow the system setting by default"),
                .polish("Make it follow the system setting by default.", after: 0.6),
                .release(processing: 0.8),
                .wait(1.2),
                .submit,
                .wait(3),
            ]),
    ]

    func frame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        return switch placement {
        case .bottom: NSRect(x: area.midX - size.width / 2, y: area.minY + 16, width: size.width, height: size.height)
        case .topRight: NSRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height)
        }
    }
}

enum DemoStep {
    case wait(Double)
    /// The trigger key goes down: the pill appears, its waveform red until the mic is live a moment later.
    case keyDown(handsFree: Bool = false)
    /// Words arrive one at a time (light grey, still changing), then the passage is finalized (grey).
    case say(String, wordsPerSecond: Double = 4.8)
    /// After `after` seconds, the oldest finalized passage is replaced by its cleaned-up version. Doesn't hold up
    /// the steps that follow.
    case polish(String, after: Double = 0.9)
    /// The key comes up: the pill polishes for `processing` seconds (and until every `polish` has landed), then the
    /// card folds away and the text is pasted into the backdrop.
    case release(processing: Double)
    /// Shows the card with fixed text, for stills.
    case card(LiveTranscript, handsFree: Bool = false)
    /// Presses Return in the backdrop's app: the terminal sends the prompt.
    case submit
}
#endif
