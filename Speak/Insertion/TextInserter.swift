import AppKit
import Carbon.HIToolbox

/// Inserts text into the focused field by pasting it, and leaves it on the clipboard.
///
/// The previous clipboard isn't restored: there's no reliable signal for when the target app has read the text
/// (see PLAN.md, Notes), and restoring too early made slow apps paste the old clipboard instead. Leaving the
/// dictation there means a paste that didn't land is one ⌘V away.
@MainActor
final class TextInserter {
    /// How long a paste keeps the clipboard before the next one may replace it. A slow app can handle ⌘V late,
    /// and would then paste the next dictation's text instead of its own.
    private static let pasteSpacing: Duration = .seconds(1)

    private var lastPaste: ContinuousClock.Instant?

    /// Puts a dictation on the clipboard and, if `paste`, pastes it. Callers go one at a time, in order (the
    /// controller chains dictations); each waits until the previous paste has had the clipboard long enough.
    func insert(_ text: String, paste: Bool = true) async {
        if let lastPaste { try? await Task.sleep(until: lastPaste + Self.pasteSpacing) }
        copy(text)
        guard paste else { return }
        postCommandV()
        lastPaste = .now
    }

    /// Puts text on the clipboard as an ordinary item, so clipboard managers keep it too. Doesn't wait for an
    /// earlier paste: this is for the user's own copies from history.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        // Exactly ⌘ — not whatever modifiers (e.g. Fn) happen to be held.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
