import AppKit
import SwiftUI

/// A borderless, non-activating panel that floats above everything (including full-screen apps)
/// without ever taking focus from the app you're dictating into.
@MainActor
final class PillPanel: NSPanel, NSWindowDelegate {
    /// Room for the text card above (or below) the pill. Clicks on the transparent parts pass through.
    private static let size = NSSize(width: 480, height: 220)
    /// Distance from the panel's bottom edge (top edge when the card opens downwards) to the pill's centre.
    private static let pillInset: CGFloat = 28
    /// The pill's centre on screen.
    private static let anchorKey = "pillAnchor"
    /// Before the text card, the panel's origin was saved instead (panel 220 × 56, pill centred).
    private static let legacyOriginKey = "pillOrigin"

    private let model: PillModel
    private var isPositioning = false
    #if DEBUG
    /// Demo scenes put the pill where their backdrop needs it, without touching the saved position.
    var demoAnchor: NSPoint?
    #endif

    init(model: PillModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        delegate = self

        let host = PillHostingView(rootView: PillView(model: model))
        host.sizingOptions = []
        host.onDoubleClick = { [weak self] in
            // In hands-free the pill has a ✕ button; a quick double-click there shouldn't also move the pill.
            guard let self, !self.model.handsFree else { return }
            self.resetPosition()
        }
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        if !isVisible {
            placeAtSavedOrDefaultPosition()
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isVisible else { return }
                self.orderOut(nil)
            }
        }
    }

    /// Whether the pill (or its card) is on screen at a point in global display coordinates (origin at the
    /// top left of the main display, as in `CGEvent.location`).
    func showsPill(atGlobal point: CGPoint) -> Bool {
        guard isVisible, let mainDisplay = NSScreen.screens.first else { return false }
        let screenPoint = NSPoint(x: point.x, y: mainDisplay.frame.maxY - point.y)
        guard frame.contains(screenPoint) else { return false }
        let inWindow = convertPoint(fromScreen: screenPoint)
        let fromTop = CGPoint(x: inWindow.x, y: frame.height - inWindow.y)
        // A little slack: the glass edge is soft and the shape may still be animating.
        return model.glassFrame.insetBy(dx: -4, dy: -4).contains(fromTop)
    }

    // MARK: Position

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning else { return }
        UserDefaults.standard.set(NSStringFromPoint(anchor(of: frame)), forKey: Self.anchorKey)
    }

    private func resetPosition() {
        isPositioning = true
        let anchor = defaultAnchor()
        model.cardBelow = false
        setFrame(frame(for: anchor), display: true, animate: true)
        isPositioning = false
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
    }

    private func placeAtSavedOrDefaultPosition() {
        isPositioning = true
        defer { isPositioning = false }
        #if DEBUG
        if let demoAnchor {
            model.cardBelow = false
            return setFrameOrigin(frame(for: demoAnchor).origin)
        }
        #endif
        var anchor = defaultAnchor()
        if let saved = savedAnchor(),
           // Only reuse it if it's still on a connected screen.
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(saved) }) {
            anchor = saved
            // Open the card downwards if there isn't room for it above the pill.
            model.cardBelow = screen.visibleFrame.maxY - anchor.y < Self.size.height - Self.pillInset
        } else {
            model.cardBelow = false
        }
        setFrameOrigin(frame(for: anchor).origin)
    }

    private func savedAnchor() -> NSPoint? {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Self.anchorKey) { return NSPointFromString(saved) }
        guard let legacy = defaults.string(forKey: Self.legacyOriginKey) else { return nil }
        defaults.removeObject(forKey: Self.legacyOriginKey)
        let origin = NSPointFromString(legacy)
        let anchor = NSPoint(x: origin.x + 110, y: origin.y + 28)
        defaults.set(NSStringFromPoint(anchor), forKey: Self.anchorKey)
        return anchor
    }

    private func frame(for anchor: NSPoint) -> NSRect {
        let y = model.cardBelow ? anchor.y + Self.pillInset - Self.size.height : anchor.y - Self.pillInset
        return NSRect(origin: NSPoint(x: anchor.x - Self.size.width / 2, y: y), size: Self.size)
    }

    private func anchor(of frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX, y: model.cardBelow ? frame.maxY - Self.pillInset : frame.minY + Self.pillInset)
    }

    private func defaultAnchor() -> NSPoint {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: screen.midX, y: screen.minY + 12 + Self.pillInset)
    }
}

private final class PillHostingView<Content: View>: NSHostingView<Content> {
    var onDoubleClick: () -> Void = {}

    /// Lets the first click land on the pill even though its window is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Caught here rather than in SwiftUI: the window-drag gesture would otherwise swallow the second click.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
            return
        }
        super.mouseDown(with: event)
    }
}
