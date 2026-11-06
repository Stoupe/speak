import AppKit
import SpeakCore
import SwiftUI

/// Where the usage stats are explained, field by field.
let usageStatsDetailsURL = URL(string: "https://github.com/Stoupe/speak#usage-stats")!
/// The code that counts and sends them.
let usageStatsCodeURL = URL(string: "https://github.com/Stoupe/speak/blob/main/Speak/App/Telemetry.swift")!

enum UsageStatsCopy {
    static let toggle = "Share anonymous usage stats"
    static let summary = "One small summary a day: how many dictations, roughly how many words, which features you "
        + "use, and your Speak, macOS and Mac versions. Never what you say, and nothing that identifies you."
    static let note = "Speak is made by one person. Seeing how many people use it, and how, is how I decide what "
        + "to fix and build next."
    /// The setup row: the note and summary in one, shorter.
    static let setup = "Speak is made by one person, and this is how I see what to fix next. Once a day: how many "
        + "dictations, roughly how many words, which features you use, and your Speak, macOS and Mac versions. "
        + "Never what you say."
}

/// "Show What's Sent": the exact report this Mac would send next, in a popover.
struct WhatsSentButton: View {
    let telemetry: Telemetry
    @State private var report: UsageReport?

    var body: some View {
        Button("Show What's Sent") { report = telemetry.preview() }
            .popover(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } }), arrowEdge: .bottom) {
                if let report { WhatsSentView(report: report) }
            }
    }
}

struct WhatsSentView: View {
    let report: UsageReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The next report from this Mac")
                .font(.headline)
            ScrollView {
                Text(String(decoding: report.json(pretty: true), as: UTF8.self))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 300)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            Text("Totals for one day, sent the day after. \"words\" is rounded to the nearest 10.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("What each field is for", destination: usageStatsDetailsURL)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 330)
    }
}

/// The links under the choice, wherever it's shown. `compact` fits a narrow column (the README links the code).
struct UsageStatsLinks: View {
    let telemetry: Telemetry
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            WhatsSentButton(telemetry: telemetry)
            Link(compact ? "Details" : "What's Sent and Why", destination: usageStatsDetailsURL)
            if !compact { Link("Read the Code", destination: usageStatsCodeURL) }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}

/// The choice, shown once to people who set Speak up before usage stats existed.
struct UsageStatsChoiceView: View {
    @Bindable var telemetry: Telemetry
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Help improve Speak")
                        .font(.title2.weight(.semibold))
                    Text(UsageStatsCopy.note)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(UsageStatsCopy.toggle, isOn: $telemetry.isEnabled)
                    .fontWeight(.medium)
                Text(UsageStatsCopy.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                UsageStatsLinks(telemetry: telemetry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            HStack {
                Text("You can change this any time in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8) // the transparent title bar already adds space above
        .frame(width: 480)
    }
}

/// The setup window's usage stats row.
struct UsageStatsSetupSection: View {
    @Bindable var telemetry: Telemetry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(UsageStatsCopy.toggle).fontWeight(.medium)
                Text(UsageStatsCopy.setup)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                UsageStatsLinks(telemetry: telemetry, compact: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Toggle(UsageStatsCopy.toggle, isOn: $telemetry.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Hosts `UsageStatsChoiceView` in a window, like `SetupWindowController`.
@MainActor
final class UsageStatsWindowController {
    private var window: NSWindow?

    func show(telemetry: Telemetry) {
        if let window {
            bringToFront(window)
            return
        }
        let view = UsageStatsChoiceView(telemetry: telemetry) { [weak self] in self?.window?.close() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(hosting.view.fittingSize)
        window.title = "Help improve Speak"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        // However it's closed, the choice has now been shown.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                telemetry.markAsked()
                self?.window = nil
            }
        }
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
