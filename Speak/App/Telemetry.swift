import Foundation
import Observation
import SpeakCore

/// Anonymous usage stats, the app side: counting, the opt-in, and sending at most one report a day.
///
/// What is counted and the report itself are in `SpeakCore/UsageStats.swift`; the README's "Usage stats" section
/// lists every field and why. Nothing is counted or sent unless all of these hold:
/// - the build has an endpoint (`SpeakTelemetryURL`, which only `Tools/release.sh` fills in, like Sparkle's feed),
/// - the person has seen the usage stats choice (setup, or the one-time window after updating),
/// - and left sharing on.
/// A report that fails to send is dropped, not retried.
@MainActor
@Observable
final class Telemetry {
    /// Whether this build can send at all. Xcode and `Tools/install.sh` builds can't.
    let isAvailable: Bool
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Preferences.usageStatsEnabled)
            if !isEnabled { forget() }
        }
    }
    private(set) var hasAsked: Bool

    @ObservationIgnored private let endpoint: URL?
    @ObservationIgnored private let ledgerURL: URL
    @ObservationIgnored private var ledger: UsageLedger
    @ObservationIgnored private var schedule: Task<Void, Never>?
    /// Read when a report is made; set by the controller, which knows whether Apple Intelligence is available.
    @ObservationIgnored var intelligenceAvailable: () -> Bool = { false }

    /// `endpoint` defaults to the build's `SpeakTelemetryURL`; only https is accepted.
    init(endpoint configured: String? = Bundle.main.object(forInfoDictionaryKey: "SpeakTelemetryURL") as? String,
         ledgerURL: URL = UsageLedger.defaultURL) {
        endpoint = URL(string: configured ?? "").flatMap { $0.scheme == "https" ? $0 : nil }
        isAvailable = endpoint != nil
        isEnabled = UserDefaults.standard.bool(forKey: Preferences.usageStatsEnabled)
        hasAsked = UserDefaults.standard.bool(forKey: Preferences.usageStatsAsked)
        self.ledgerURL = ledgerURL
        ledger = UsageLedger.load(from: ledgerURL)
    }

    var isSharing: Bool { isAvailable && hasAsked && isEnabled }

    /// The choice has been shown (setup, or the window after an update). Until then nothing is counted or sent.
    func markAsked() {
        guard !hasAsked else { return }
        hasAsked = true
        UserDefaults.standard.set(true, forKey: Preferences.usageStatsAsked)
        sendIfDue()
    }

    /// Sends any finished day now, then checks hourly, so a Mac that stays on past midnight still reports.
    func start() {
        guard isAvailable, schedule == nil else { return }
        sendIfDue()
        schedule = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                sendIfDue()
            }
        }
    }

    func record(_ outcome: DictationOutcome) {
        guard isSharing else { return }
        ledger.record(outcome, today: today)
        ledger.save(to: ledgerURL)
        sendIfDue()
    }

    /// What would be sent: the finished day waiting to go, else today so far.
    func preview() -> UsageReport {
        let day = ledger.pending ?? ledger.current ?? UsageLedger.Day(day: today, counts: UsageCounts())
        return UsageReport(day: day.day, counts: day.counts, environment: environment())
    }

    private func sendIfDue() {
        guard isSharing, let endpoint else { return }
        guard let day = ledger.takePending(today: today) else { return }
        // Dropped from the ledger before sending: one attempt, no retries.
        ledger.save(to: ledgerURL)
        let report = UsageReport(day: day.day, counts: day.counts, environment: environment())
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = report.json()
        Task {
            do {
                let (_, response) = try await Self.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                log.info("usage report for \(day.day, privacy: .public): HTTP \(status)")
            } catch {
                log.info("usage report for \(day.day, privacy: .public) not sent: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Clears counts kept so far, when sharing is turned off.
    private func forget() {
        ledger = UsageLedger()
        try? FileManager.default.removeItem(at: ledgerURL)
    }

    private var today: String { UsageLedger.dayString(.now) }

    private func environment() -> UsageEnvironment {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return UsageEnvironment(
            app: info["CFBundleShortVersionString"] as? String ?? "0",
            build: Int(info["CFBundleVersion"] as? String ?? "") ?? 0,
            os: "\(os.majorVersion).\(os.minorVersion)",
            chip: UsageEnvironment.cleanChip(Self.chipName),
            locale: UsageEnvironment.localeTag(
                language: Locale.current.language.languageCode?.identifier,
                region: Locale.current.region?.identifier),
            trigger: TriggerKey.current.rawValue,
            polish: UserDefaults.standard.bool(forKey: Preferences.polishEnabled),
            intelligence: intelligenceAvailable())
    }

    /// No cookies, cache or stored credentials: each report goes out on its own.
    private static let session = URLSession(configuration: .ephemeral)

    private static let chipName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }()
}
