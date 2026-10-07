import Foundation

/// Input to the trigger state machine.
public enum TriggerEvent: Equatable, Sendable {
    case fnDown
    case fnUp
    /// Any other key pressed (Fn+arrow, typing, …).
    case otherKey
    case escape
    /// The double-tap window opened by a short tap has elapsed.
    case tapWindowElapsed(id: Int)
}

/// What the controller should do in response to an event.
public enum TriggerAction: Equatable, Sendable {
    /// Start recording. Issued on the very first Fn down so no audio is lost.
    case startRecording
    /// Stop recording and process what was said.
    case commit
    /// Stop recording and throw it away.
    case cancel
    /// A second tap arrived in time: keep recording until Fn is pressed again.
    case enterHandsFree
    /// Call back with `.tapWindowElapsed(id:)` after `seconds`.
    case scheduleTapWindow(id: Int, seconds: TimeInterval)
}

/// Turns raw Fn key events into recording actions.
///
/// - Hold Fn (≥ `holdThreshold`), release → commit.
/// - Tap Fn twice quickly → hands-free; tap Fn again to commit.
/// - A single short tap → cancelled (it was probably an accident).
/// - Fn + another key while holding → cancelled (it was a shortcut).
/// - Escape at any point → cancelled.
public struct TriggerStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case holding(since: TimeInterval)
        /// Short tap released; waiting to see if a second tap follows.
        case awaitingSecondTap(id: Int)
        /// Second tap is down; hands-free starts once it's released.
        case secondTapDown
        case handsFree
    }

    public var holdThreshold: TimeInterval
    public var doubleTapWindow: TimeInterval
    public private(set) var state: State = .idle
    private var nextTapID = 0

    public init(holdThreshold: TimeInterval = 0.25, doubleTapWindow: TimeInterval = 0.3) {
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    public var isActive: Bool { state != .idle }

    /// Forces the machine back to idle without emitting actions (e.g. after an error).
    public mutating func reset() { state = .idle }

    public mutating func handle(_ event: TriggerEvent, at now: TimeInterval) -> [TriggerAction] {
        switch (state, event) {
        case (.idle, .fnDown):
            state = .holding(since: now)
            return [.startRecording]

        case (.holding(let since), .fnUp):
            if now - since >= holdThreshold {
                state = .idle
                return [.commit]
            }
            nextTapID += 1
            state = .awaitingSecondTap(id: nextTapID)
            return [.scheduleTapWindow(id: nextTapID, seconds: doubleTapWindow)]

        case (.awaitingSecondTap, .fnDown):
            state = .secondTapDown
            return [.enterHandsFree]

        case (.awaitingSecondTap(let id), .tapWindowElapsed(let elapsed)) where id == elapsed:
            state = .idle
            return [.cancel]

        case (.secondTapDown, .fnUp):
            state = .handsFree
            return []

        case (.handsFree, .fnDown):
            state = .idle
            return [.commit]

        case (.holding, .otherKey), (.awaitingSecondTap, .otherKey), (.secondTapDown, .otherKey):
            state = .idle
            return [.cancel]

        case (.idle, .escape):
            return []

        case (_, .escape):
            state = .idle
            return [.cancel]

        default:
            // Stale timers, Fn up after a hands-free commit, other keys while hands-free, …
            return []
        }
    }
}
