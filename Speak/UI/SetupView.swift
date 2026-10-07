import AppKit
import AVFAudio
import ApplicationServices
import SpeakCore
import SwiftUI

/// Live permission/setting status for the setup window, re-read every second while it's open.
@MainActor
@Observable
final class SetupStatus {
    var microphone = AVAudioApplication.shared.recordPermission
    var accessibility = AXIsProcessTrusted()
    var globeKeyDoesNothing = SetupStatus.readGlobeKeySetting()
    var trigger = TriggerKey.current

    var requiredStepsDone: Bool {
        microphone == .granted && accessibility && (trigger != .fn || globeKeyDoesNothing)
    }

    func refresh() {
        microphone = AVAudioApplication.shared.recordPermission
        accessibility = AXIsProcessTrusted()
        globeKeyDoesNothing = Self.readGlobeKeySetting()
        trigger = TriggerKey.current
    }

    /// System Settings → Keyboard → "Press 🌐 key to": 0 is "Do Nothing".
    static func readGlobeKeySetting() -> Bool {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int == 0
    }
}

struct SetupView: View {
    let controller: DictationController
    let status: SetupStatus
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up Speak")
                        .font(.title2.weight(.semibold))
                    Text("Speak needs a couple of permissions to hear you and type for you. Everything stays on this Mac.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                SetupRow(
                    symbol: "mic",
                    title: "Microphone",
                    detail: "To hear you while you hold the trigger key. Audio is never saved or sent anywhere.",
                    done: status.microphone == .granted,
                    actionTitle: status.microphone == .undetermined ? "Allow…" : "Open Settings…",
                    action: requestMicrophone)
                Divider().padding(.leading, 44)
                SetupRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "To notice the trigger key and paste text where your cursor is.",
                    done: status.accessibility,
                    actionTitle: "Open Settings…",
                    action: requestAccessibility)
                if status.trigger == .fn {
                    Divider().padding(.leading, 44)
                    SetupRow(
                        symbol: "globe",
                        title: "Globe key",
                        detail: "Set “Press 🌐 key to” to “Do Nothing”, so fn doesn't also open emoji or dictation.",
                        done: status.globeKeyDoesNothing,
                        actionTitle: "Open Settings…",
                        action: { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") })
                }
                Divider().padding(.leading, 44)
                SetupRow(
                    symbol: "sparkles",
                    title: "Apple Intelligence",
                    detail: polishDetail,
                    done: controller.polisherAvailability == .available,
                    optional: true,
                    actionTitle: "Open Settings…",
                    action: { open("x-apple.systempreferences:com.apple.Siri-Settings.extension") })
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            HStack {
                Text("Hold \(status.trigger.name) to dictate. Double-tap for hands-free.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(status.requiredStepsDone ? "Done" : "Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .task {
            while !Task.isCancelled {
                status.refresh()
                controller.refreshPolisherAvailability()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var polishDetail: String {
        switch controller.polisherAvailability {
        case .available:
            "Optional. Tidies up your text on this Mac."
        case .unavailable(let reason):
            "Optional. Tidies up your text on this Mac. Without it Speak pastes exactly what it heard. (\(reason))"
        }
    }

    private func requestMicrophone() {
        if status.microphone == .undetermined {
            Task {
                _ = await AVAudioApplication.requestRecordPermission()
                status.refresh()
                controller.refreshPermissions()
            }
        } else {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }

    private func requestAccessibility() {
        // The prompt adds Speak to the Accessibility list (switched off) and offers to open Settings.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

private struct SetupRow: View {
    let symbol: String
    let title: String
    let detail: String
    let done: Bool
    var optional = false
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .tint(optional ? nil : .accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.smooth, value: done)
    }
}

/// Hosts `SetupView` in a regular window, since a menu bar app has no scene-based window to open from code.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?

    func show(controller: DictationController) {
        if let window {
            bringToFront(window)
            return
        }
        let status = SetupStatus()
        let view = SetupView(controller: controller, status: status) { [weak self] in
            UserDefaults.standard.set(true, forKey: Preferences.setupCompleted)
            controller.refreshPermissions()
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        // Size to the content first so `center()` centres the real window, not a placeholder size.
        window.setContentSize(hosting.view.fittingSize)
        window.title = "Set up Speak"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        bringToFront(window)
    }

    /// A menu bar app isn't the active app, and macOS may decline `activate()`, so also order the window
    /// front regardless — otherwise it opens hidden behind whatever you're using.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
