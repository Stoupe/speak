#if DEBUG
import AppKit
import SpeakCore
import SwiftUI

/// Renders the setup, usage stats and Settings views to PNG files offscreen, then quits: a way to check layout
/// (and measure the Settings form) without opening windows or starting the mic or key tap.
///
///   build/DerivedData/Build/Products/Debug/Speak.app/Contents/MacOS/Speak -snapshot /path/to/folder
///
/// Usage stats are shown as if this were a release build, with an endpoint that can't be reached and a throwaway
/// ledger, so nothing is ever sent.
@MainActor
enum Snapshot {
    static var requestedDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-snapshot"), arguments.indices.contains(index + 1) else { return nil }
        return URL(filePath: arguments[index + 1])
    }

    static func makeController() -> DictationController {
        let ledger = FileManager.default.temporaryDirectory.appending(path: "speak-snapshot-usage.json")
        try? FileManager.default.removeItem(at: ledger)
        return DictationController(telemetry: Telemetry(endpoint: "https://example.invalid/v1/report", ledgerURL: ledger))
    }

    static func run(controller: DictationController, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let updater = Updater()

        await render(SetupView(controller: controller, status: SetupStatus(), bringToFront: {}, onDone: {}),
                     to: directory.appending(path: "setup.png"))
        await render(UsageStatsChoiceView(telemetry: controller.telemetry, onDone: {}),
                     to: directory.appending(path: "usage-window.png"))
        var counts = UsageCounts()
        for words in [12, 40, 7] { counts.add(.finished(words: words, handsFree: false)) }
        counts.add(.finished(words: 85, handsFree: true))
        counts.add(.empty)
        let environment = UsageEnvironment(app: "0.3", build: 40, os: "27.0", chip: "Apple M1", locale: "en-NZ",
                                           trigger: "fn", polish: true, intelligence: true)
        await render(WhatsSentView(report: UsageReport(day: "2026-11-05", counts: counts, environment: environment)),
                     to: directory.appending(path: "whats-sent.png"))

        // Settings twice, unconstrained, with and without the usage stats section, to measure its height.
        SettingsView.snapshotHeight = 1000
        await render(SettingsView(controller: controller, updater: updater),
                     to: directory.appending(path: "settings-with-stats.png"))
        let without = DictationController(telemetry: Telemetry(endpoint: nil))
        await render(SettingsView(controller: without, updater: updater),
                     to: directory.appending(path: "settings-without-stats.png"))
        SettingsView.snapshotHeight = nil
        await render(SettingsView(controller: controller, updater: updater),
                     to: directory.appending(path: "settings.png"))
        exit(0)
    }

    private static func render<V: View>(_ view: V, to url: URL) async {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("\(url.lastPathComponent): \(Int(size.width))×\(Int(size.height))")
    }
}
#endif
