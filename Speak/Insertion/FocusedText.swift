import ApplicationServices
import Foundation

/// Reads around the caret of the focused text field via Accessibility. Many apps (Electron, some
/// browsers, terminals) don't expose this; every function returns nil in that case.
enum FocusedText {
    /// The character immediately before the caret/selection, or nil if unknown or at the start.
    static func characterBeforeCaret() -> Character? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location > 0 else { return nil }

        // Ranges are UTF-16 units: read two so a preceding emoji (surrogate pair) comes back whole.
        let length = min(range.location, 2)
        var previous = CFRange(location: range.location - length, length: length)
        guard let previousValue = AXValueCreate(.cfRange, &previous) else { return nil }
        var string: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, previousValue, &string) == .success,
              let text = string as? String, let last = text.last,
              last != "\u{FFFD}"
        else { return nil }
        return last
    }

    /// Prefixes a space when the new text would otherwise butt up against the previous word.
    static func withLeadingSpaceIfNeeded(_ text: String, after previous: Character?) -> String {
        guard let previous, let first = text.first else { return text }
        if previous.isWhitespace || "([{\"'“‘/-".contains(previous) { return text }
        if first.isWhitespace || ".,;:!?)]}".contains(first) { return text }
        return " " + text
    }
}
