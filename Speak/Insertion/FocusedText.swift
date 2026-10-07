import ApplicationServices
import Foundation

/// Reads the text around the caret of the focused field via Accessibility. Many apps (Electron, some
/// browsers, terminals) don't expose this; the values are nil in that case.
enum FocusedText {
    struct Surroundings {
        /// Up to three characters before the caret; empty at the start of the field.
        var before: String?
        /// The character after the caret/selection; nil at the end of the field or if unknown.
        var after: Character?
    }

    static func surroundings() -> Surroundings {
        guard let element = focusedElement(), let selection = selectedRange(of: element) else {
            return Surroundings()
        }
        let beforeLength = min(selection.location, 3)
        let before = beforeLength == 0
            ? ""
            : string(in: element, range: CFRange(location: selection.location - beforeLength, length: beforeLength))
        let afterText = string(in: element, range: CFRange(location: selection.location + selection.length, length: 2))
        return Surroundings(before: before.map(dropBrokenSurrogate), after: afterText?.first)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Ranges are UTF-16 units, so a range edge can split an emoji; `dropBrokenSurrogate` cleans that up.
    private static func string(in element: AXUIElement, range: CFRange) -> String? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func dropBrokenSurrogate(_ text: String) -> String {
        String(text.drop(while: { $0 == "\u{FFFD}" }))
    }
}
