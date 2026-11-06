import Foundation

/// UserDefaults keys, shared by `@AppStorage` in views and direct reads in the controller.
enum Preferences {
    static let microphoneUID = "microphoneUID"
    static let triggerKey = "triggerKey"
    static let setupCompleted = "setupCompleted"
    static let polishEnabled = "polishEnabled"
    static let soundsEnabled = "soundsEnabled"
    /// Add a space after each pasted dictation.
    static let trailingSpace = "trailingSpace"
    /// Newline-separated names and terms.
    static let dictionary = "dictionary"
    /// Anonymous usage stats (see `Telemetry`): on unless turned off, but nothing is sent until the choice has been
    /// shown, which `usageStatsAsked` records.
    static let usageStatsEnabled = "usageStatsEnabled"
    static let usageStatsAsked = "usageStatsAsked"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            polishEnabled: true,
            soundsEnabled: true,
            trailingSpace: true,
            usageStatsEnabled: true,
        ])
    }

    static var dictionaryWords: [String] {
        (UserDefaults.standard.string(forKey: dictionary) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
