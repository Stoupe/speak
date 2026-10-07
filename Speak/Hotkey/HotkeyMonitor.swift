import AppKit
import CoreGraphics
import SpeakCore

/// Watches the Fn key system-wide with a CGEventTap. Requires Accessibility permission.
///
/// The tap runs on the main run loop, so the callback is already on the main thread.
@MainActor
final class HotkeyMonitor {
    /// Receives Fn / other-key / escape events.
    var onEvent: ((TriggerEvent) -> Void)?
    /// While true, Escape is swallowed (so it doesn't also close a dialog in the frontmost app).
    var swallowsEscape = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fnIsDown = false

    var isRunning: Bool { tap != nil }

    /// Returns false if the tap couldn't be created (usually missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        fnIsDown = false
    }

    /// Returns true to let the event through, false to swallow it.
    fileprivate func handle(_ event: TapEvent) -> Bool {
        let type = event.type
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow or interrupted taps; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true

        case .flagsChanged:
            guard event.keyCode == Self.fnKeyCode else { return true }
            let down = event.flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return true }
            fnIsDown = down
            onEvent?(down ? .fnDown : .fnUp)
            return true

        case .keyDown:
            // Ignore our own synthetic ⌘V and other injected events.
            guard event.sourcePID != Int64(getpid()) else { return true }
            if event.keyCode == Self.escapeKeyCode {
                // Read before dispatching: handling Escape ends the dictation and clears the flag.
                let swallow = swallowsEscape
                onEvent?(.escape)
                return !swallow
            }
            onEvent?(.otherKey)
            return true

        default:
            return true
        }
    }

    private static let fnKeyCode: Int64 = 63 // kVK_Function
    private static let escapeKeyCode: Int64 = 53 // kVK_Escape
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let tapEvent = TapEvent(
        type: type,
        keyCode: event.getIntegerValueField(.keyboardEventKeycode),
        flags: event.flags,
        sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID))
    let passThrough = MainActor.assumeIsolated { monitor.handle(tapEvent) }
    return passThrough ? Unmanaged.passUnretained(event) : nil
}

/// The parts of a CGEvent the monitor needs, as plain values.
struct TapEvent: Sendable {
    var type: CGEventType
    var keyCode: Int64
    var flags: CGEventFlags
    var sourcePID: Int64
}
