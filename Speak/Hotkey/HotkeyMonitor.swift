import AppKit
import CoreGraphics
import SpeakCore

/// Watches the trigger key (Fn by default) system-wide with a CGEventTap. Requires Accessibility permission.
///
/// The tap runs on its own thread so that main-thread work (starting the mic, Accessibility queries)
/// never delays keystrokes system-wide. Events are delivered to the main queue.
final class HotkeyMonitor: @unchecked Sendable {
    // `@unchecked`: `onEvent` is set once before `start()`; everything mutable afterwards is in `state`.

    /// Receives Fn / other-key / escape events on the main queue, with the system uptime at which the key
    /// actually changed (the main thread may be busy, so handling time isn't a reliable timestamp).
    var onEvent: (@MainActor (TriggerEvent, TimeInterval) -> Void)?

    private struct State {
        var tap: CFMachPort?
        var triggerIsDown = false
        var swallowsEscape = false
    }

    private let state = Locked(State())

    var isRunning: Bool { state.withLock { $0.tap != nil } }

    /// While true, Escape is swallowed (so it doesn't also close a dialog in the frontmost app).
    var swallowsEscape: Bool {
        get { state.withLock { $0.swallowsEscape } }
        set { state.withLock { $0.swallowsEscape = newValue } }
    }

    /// Returns false if the tap couldn't be created (usually missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        state.withLock { $0.tap = tap }

        // CF types aren't Sendable; both are handed to the tap thread once and not touched here again.
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        nonisolated(unsafe) let threadTap = tap
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: threadTap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Speak.HotkeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// Runs on the tap thread. Returns true to let the event through, false to swallow it.
    fileprivate func handle(_ event: TapEvent) -> Bool {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow or interrupted taps; turn it straight back on.
            let missedFnUp = state.withLock { state -> Bool in
                if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                // Key-ups may have been missed while it was off.
                let held = TriggerKey.current.isDown(CGEventSource.flagsState(.combinedSessionState))
                guard state.triggerIsDown, !held else { return false }
                state.triggerIsDown = false
                return true
            }
            if missedFnUp { deliver(.fnUp) }
            return true

        case .flagsChanged:
            let trigger = TriggerKey.current
            guard event.keyCode == trigger.keyCode else { return true }
            let down = trigger.isDown(event.flags)
            let changed = state.withLock { state -> Bool in
                guard down != state.triggerIsDown else { return false }
                state.triggerIsDown = down
                return true
            }
            if changed { deliver(down ? .fnDown : .fnUp) }
            return true

        case .keyDown:
            // Ignore our own synthetic ⌘V and other injected events.
            guard event.sourcePID != Int64(getpid()) else { return true }
            // Releasing Fn after a quick tap makes macOS emit a synthetic Globe key press; it isn't "another key".
            guard event.keyCode != Self.globeKeyCode else { return true }
            if event.keyCode == Self.escapeKeyCode {
                deliver(.escape)
                return !swallowsEscape
            }
            deliver(.otherKey)
            return true

        default:
            return true
        }
    }

    private func deliver(_ event: TriggerEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onEvent?(event, time) }
        }
    }

    private static let escapeKeyCode: Int64 = 53 // kVK_Escape
    private static let globeKeyCode: Int64 = 179 // emitted by the system after a Fn/Globe tap
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
    return monitor.handle(tapEvent) ? Unmanaged.passUnretained(event) : nil
}

/// The parts of a CGEvent the monitor needs, as plain values.
struct TapEvent: Sendable {
    var type: CGEventType
    var keyCode: Int64
    var flags: CGEventFlags
    var sourcePID: Int64
}
