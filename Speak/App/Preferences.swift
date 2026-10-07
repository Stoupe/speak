import Foundation

/// UserDefaults keys, shared by `@AppStorage` in views and direct reads in the controller.
enum Preferences {
    static let microphoneUID = "microphoneUID"
    static let triggerKey = "triggerKey"
    static let setupCompleted = "setupCompleted"
    static let polishEnabled = "polishEnabled"
    static let soundsEnabled = "soundsEnabled"
    /// Newline-separated names and terms.
    static let dictionary = "dictionary"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            polishEnabled: true,
            soundsEnabled: true,
        ])
    }

    static var dictionaryWords: [String] {
        (UserDefaults.standard.string(forKey: dictionary) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
