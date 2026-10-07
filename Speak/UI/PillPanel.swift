import AppKit
import SwiftUI

/// A borderless, non-activating panel that floats above everything (including full-screen apps)
/// without ever taking focus from the app you're dictating into.
@MainActor
final class PillPanel: NSPanel, NSWindowDelegate {
    private static let size = NSSize(width: 220, height: 56)
    private static let originKey = "pillOrigin"

    private let model: PillModel
    private var isPositioning = false

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
            context.duration = 0.15
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

    // MARK: Position

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning else { return }
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.originKey)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            isPositioning = true
            animator().setFrameOrigin(defaultOrigin())
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isPositioning = false
                // A trailing windowDidMove may have re-saved the default position; it isn't a user choice.
                UserDefaults.standard.removeObject(forKey: Self.originKey)
            }
        }
    }

    private func placeAtSavedOrDefaultPosition() {
        isPositioning = true
        defer { isPositioning = false }
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let origin = NSPointFromString(saved)
            let frame = NSRect(origin: origin, size: Self.size)
            // Only reuse it if it's still on a connected screen.
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                setFrameOrigin(origin)
                return
            }
        }
        setFrameOrigin(defaultOrigin())
    }

    private func defaultOrigin() -> NSPoint {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: screen.midX - Self.size.width / 2, y: screen.minY + 12)
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
