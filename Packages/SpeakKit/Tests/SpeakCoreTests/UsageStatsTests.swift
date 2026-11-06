import Foundation
import Testing
@testable import SpeakCore

@Suite struct UsageStatsTests {
    static let environment = UsageEnvironment(
        app: "0.3", build: 40, os: "27.0", chip: "Apple M1", locale: "en-NZ", trigger: "fn",
        polish: true, intelligence: true)

    @Test func countsOutcomes() {
        var counts = UsageCounts()
        counts.add(.finished(words: 12, handsFree: false))
        counts.add(.finished(words: 30, handsFree: true))
        counts.add(.empty)
        counts.add(.cancelled)
        #expect(counts.dictations == 2)
        #expect(counts.words == 42)
        #expect(counts.hold == 1)
        #expect(counts.handsFree == 1)
        #expect(counts.empty == 1)
        #expect(counts.cancelled == 1)
    }

    @Test func reportRoundsWords() {
        var counts = UsageCounts()
        counts.add(.finished(words: 44, handsFree: false))
        #expect(UsageReport(day: "2026-11-05", counts: counts, environment: Self.environment).words == 40)
        counts.add(.finished(words: 1, handsFree: false))
        #expect(UsageReport(day: "2026-11-05", counts: counts, environment: Self.environment).words == 50)
        #expect(UsageReport(day: "2026-11-05", counts: UsageCounts(), environment: Self.environment).words == 0)
    }

    @Test func pendingOnlyOnceTheDayIsOver() {
        var ledger = UsageLedger()
        ledger.record(.finished(words: 5, handsFree: false), today: "2026-11-05")
        #expect(ledger.takePending(today: "2026-11-05") == nil)
        ledger.record(.empty, today: "2026-11-05")

        let pending = ledger.takePending(today: "2026-11-06")
        #expect(pending?.day == "2026-11-05")
        #expect(pending?.counts.dictations == 1)
        #expect(pending?.counts.empty == 1)
        // Taken means gone, sent or not: no retries.
        #expect(ledger.takePending(today: "2026-11-06") == nil)
        #expect(ledger.current == nil)
    }

    @Test func keepsOnlyTheLatestUnsentDay() {
        var ledger = UsageLedger()
        ledger.record(.empty, today: "2026-11-01")
        ledger.record(.cancelled, today: "2026-11-02")
        ledger.record(.empty, today: "2026-11-03")
        let pending = ledger.takePending(today: "2026-11-03")
        #expect(pending?.day == "2026-11-02")
        #expect(pending?.counts.cancelled == 1)
        #expect(ledger.current?.day == "2026-11-03")
    }

    @Test func savesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "speak-usage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var ledger = UsageLedger()
        ledger.record(.finished(words: 3, handsFree: true), today: "2026-11-05")
        ledger.save(to: url)
        #expect(UsageLedger.load(from: url) == ledger)
        #expect(UsageLedger.load(from: url.appending(path: "missing")) == UsageLedger())
    }

    @Test func dayStringUsesTheLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        // 2026-11-05 20:00 UTC is already the 6th in Auckland.
        let date = Date(timeIntervalSince1970: 1_793_908_800)
        #expect(UsageLedger.dayString(date, calendar: calendar) == "2026-11-06")
    }

    @Test func cleansEnvironmentValues() {
        #expect(UsageEnvironment.cleanChip("Apple M1 Pro") == "Apple M1 Pro")
        #expect(UsageEnvironment.cleanChip("  Apple  M4\t(R)™ ") == "Apple M4 R")
        #expect(UsageEnvironment.cleanChip("") == "Unknown")
        #expect(UsageEnvironment.localeTag(language: "en", region: "NZ") == "en-NZ")
        #expect(UsageEnvironment.localeTag(language: "es", region: "419") == "es-419")
        #expect(UsageEnvironment.localeTag(language: "en", region: nil) == "en")
        #expect(UsageEnvironment.localeTag(language: nil, region: "NZ") == "und")
    }

    /// The report's JSON keys, as the server and the README see them.
    static var reportKeys: Set<String> {
        let report = UsageReport(day: "2026-11-05", counts: UsageCounts(), environment: environment)
        let object = try? JSONSerialization.jsonObject(with: report.json()) as? [String: Any]
        return Set(object?.keys.map { $0 } ?? [])
    }

    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Every field sent is explained in the README, and the README lists nothing that isn't sent.
    @Test func readmeListsExactlyTheReportFields() throws {
        let readme = try String(contentsOf: Self.repo.appending(path: "README.md"), encoding: .utf8)
        let section = try #require(readme.components(separatedBy: "\n### Usage stats\n").dropFirst().first)
            .components(separatedBy: "\n## ").first ?? ""
        let documented = Set(section.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("| `"), let end = line.dropFirst(3).firstIndex(of: "`") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 3)..<end])
        })
        #expect(documented == Self.reportKeys)
    }

    /// The server accepts exactly these fields and nothing else.
    @Test func serverAcceptsExactlyTheReportFields() throws {
        let source = try String(contentsOf: Self.repo.appending(path: "server/telemetry/src/report.ts"), encoding: .utf8)
        let list = try #require(source.components(separatedBy: "const FIELDS = [").dropFirst().first?
            .components(separatedBy: "]").first)
        let fields = Set(list.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }.filter { !$0.isEmpty })
        #expect(fields == Self.reportKeys)
    }
}
