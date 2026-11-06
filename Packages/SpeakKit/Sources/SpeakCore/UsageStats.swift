import Foundation

// Anonymous usage stats: what Speak counts, and the one report it sends per day when sharing is on.
//
// Counting happens on this Mac only. At most once a day, the previous day's totals go to the endpoint as a
// `UsageReport`: no text, no audio, no app names, no identifier. A report that fails to send is dropped, not
// retried. The app side (when to send, the network request, the opt-in) is `Speak/App/Telemetry.swift`; the server
// that receives reports is `server/telemetry/`. The README's "Usage stats" section lists every field, and a test
// keeps that table in step with `UsageReport`.

/// How one dictation ended, as far as the stats are concerned.
public enum DictationOutcome: Equatable, Sendable {
    /// Text was pasted (or copied, if the app changed).
    case finished(words: Int, handsFree: Bool)
    /// Nothing was recognized.
    case empty
    /// Cancelled with Esc or the pill's cancel button.
    case cancelled
}

/// One day's totals.
public struct UsageCounts: Codable, Equatable, Sendable {
    public var dictations = 0
    /// Exact here; rounded to the nearest 10 in the report.
    public var words = 0
    public var hold = 0
    public var handsFree = 0
    public var empty = 0
    public var cancelled = 0

    public init() {}

    public var isEmpty: Bool { self == UsageCounts() }

    public mutating func add(_ outcome: DictationOutcome) {
        switch outcome {
        case .finished(let words, let handsFree):
            dictations += 1
            self.words += max(0, words)
            if handsFree { self.handsFree += 1 } else { hold += 1 }
        case .empty:
            empty += 1
        case .cancelled:
            cancelled += 1
        }
    }
}

/// Facts about this Mac and its settings that go into a report, read when it's made.
public struct UsageEnvironment: Equatable, Sendable {
    public var app: String
    public var build: Int
    public var os: String
    public var chip: String
    public var locale: String
    public var trigger: String
    public var polish: Bool
    public var intelligence: Bool

    public init(app: String, build: Int, os: String, chip: String, locale: String, trigger: String,
                polish: Bool, intelligence: Bool) {
        self.app = app
        self.build = build
        self.os = os
        self.chip = chip
        self.locale = locale
        self.trigger = trigger
        self.polish = polish
        self.intelligence = intelligence
    }
}

/// Exactly what is sent. Every property is listed, with its reason, in the README's "Usage stats" table.
public struct UsageReport: Codable, Equatable, Sendable {
    /// Report format version.
    public var v = 1
    /// The local date the counts are for, YYYY-MM-DD.
    public var day: String
    public var app: String
    public var build: Int
    /// macOS major.minor.
    public var os: String
    public var chip: String
    /// Language and region, e.g. "en-NZ".
    public var locale: String
    public var trigger: String
    /// Whether "Polish text" is on.
    public var polish: Bool
    /// Whether Apple Intelligence is available for polishing.
    public var intelligence: Bool
    public var dictations: Int
    /// Rounded to the nearest 10.
    public var words: Int
    public var hold: Int
    public var handsFree: Int
    public var empty: Int
    public var cancelled: Int

    public init(day: String, counts: UsageCounts, environment env: UsageEnvironment) {
        self.day = day
        app = env.app
        build = env.build
        os = env.os
        chip = env.chip
        locale = env.locale
        trigger = env.trigger
        polish = env.polish
        intelligence = env.intelligence
        dictations = counts.dictations
        words = Int((Double(counts.words) / 10).rounded()) * 10
        hold = counts.hold
        handsFree = counts.handsFree
        empty = counts.empty
        cancelled = counts.cancelled
    }

    /// The JSON body, keys sorted, as sent and as shown in "Show What's Sent".
    public func json(pretty: Bool = false) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// Today's running totals plus, once a day has ended, its totals waiting to be sent. Persisted as a small JSON file.
public struct UsageLedger: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var day: String
        public var counts: UsageCounts

        public init(day: String, counts: UsageCounts) {
            self.day = day
            self.counts = counts
        }
    }

    public private(set) var current: Day?
    /// The most recent finished day with any activity, not yet sent.
    public private(set) var pending: Day?

    public init() {}

    /// Moves the current day to `pending` once `today` has moved on. Only the latest finished day is kept: one
    /// report a day at most, and an older unsent one is dropped.
    public mutating func rollOver(today: String) {
        guard let current, current.day != today else { return }
        if !current.counts.isEmpty { pending = current }
        self.current = nil
    }

    public mutating func record(_ outcome: DictationOutcome, today: String) {
        rollOver(today: today)
        var day = current ?? Day(day: today, counts: UsageCounts())
        day.counts.add(outcome)
        current = day
    }

    /// Removes and returns the finished day to send, if there is one.
    public mutating func takePending(today: String) -> Day? {
        rollOver(today: today)
        defer { pending = nil }
        return pending
    }

    /// The local date as YYYY-MM-DD.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func load(from url: URL) -> UsageLedger {
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data)
        else { return UsageLedger() }
        return ledger
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Speak/usage.json")
    }
}

extension UsageEnvironment {
    /// Keeps only what the server accepts: letters, digits and spaces, at most 40 characters.
    public static func cleanChip(_ raw: String) -> String {
        let kept = String(raw.compactMap { character -> Character? in
            if character.isWhitespace { return " " }
            return character.isASCII && (character.isLetter || character.isNumber) ? character : nil
        }).split(separator: " ").joined(separator: " ")
        return kept.isEmpty ? "Unknown" : String(kept.prefix(40))
    }

    /// "en-NZ" from a language code and region; just the language without a region.
    public static func localeTag(language: String?, region: String?) -> String {
        let language = (language ?? "").filter { $0.isASCII && $0.isLetter }
        guard (2...3).contains(language.count) else { return "und" }
        let region = (region ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return (2...4).contains(region.count) ? "\(language)-\(region)" : language
    }
}
