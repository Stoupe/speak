import CoreGraphics
import Foundation

/// The key held to dictate. Right-hand modifiers are distinguished from left via device-dependent flag bits.
enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "right ⌥"
        case .rightCommand: "right ⌘"
        }
    }

    var menuTitle: String {
        switch self {
        case .fn: "fn (Globe)"
        case .rightOption: "Right Option ⌥"
        case .rightCommand: "Right Command ⌘"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fn: 63 // kVK_Function
        case .rightOption: 61 // kVK_RightOption
        case .rightCommand: 54 // kVK_RightCommand
        }
    }

    /// Whether the key is down, given the flags of a flagsChanged event for `keyCode`.
    func isDown(_ flags: CGEventFlags) -> Bool {
        switch self {
        case .fn: flags.contains(.maskSecondaryFn)
        case .rightOption: flags.rawValue & 0x40 != 0 // NX_DEVICERALTKEYMASK
        case .rightCommand: flags.rawValue & 0x10 != 0 // NX_DEVICERCMDKEYMASK
        }
    }

    static var current: TriggerKey {
        UserDefaults.standard.string(forKey: Preferences.triggerKey).flatMap(TriggerKey.init(rawValue:)) ?? .fn
    }
}
