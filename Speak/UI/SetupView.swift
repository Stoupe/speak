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
        let key = status.trigger.name
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Speak")
                        .font(.title2.weight(.semibold))
                    Text("Hold \(key) and talk. When you let go, Speak types what you said wherever your cursor is.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It all runs on this Mac. Your voice is never saved or sent anywhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SetupSection(title: "Speak needs") {
                SetupRow(
                    symbol: "mic",
                    title: "Microphone",
                    detail: "To hear you while you hold \(key).",
                    done: status.microphone == .granted,
                    actionTitle: status.microphone == .undetermined ? "Allow" : "Open Settings",
                    action: requestMicrophone)
                Divider().padding(.leading, 44)
                SetupRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "To notice when you press \(key), and to type into other apps.",
                    done: status.accessibility,
                    actionTitle: "Open Settings",
                    action: requestAccessibility)
            }

            SetupSection(title: "Recommended") {
                if status.trigger == .fn {
                    SetupRow(
                        symbol: "globe",
                        title: "Free up the fn key",
                        detail: "In Keyboard settings, set the 🌐 key to Do Nothing so it doesn't also open emoji.",
                        done: status.globeKeyDoesNothing,
                        actionTitle: "Open Settings",
                        action: { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") })
                    Divider().padding(.leading, 44)
                }
                SetupRow(
                    symbol: "sparkles",
                    title: "Apple Intelligence",
                    detail: "Removes ums, repeats and false starts. Without it, Speak types exactly what it heard.",
                    note: polishNote,
                    done: controller.polisherAvailability == .available,
                    actionTitle: "Open Settings",
                    action: { open("x-apple.systempreferences:com.apple.Siri-Settings.extension") })
            }

            HStack {
                Text("Double-tap \(key) to keep listening without holding it. Esc cancels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button(status.requiredStepsDone ? "Get Started" : "Set Up Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8) // the transparent title bar already adds space above
        .frame(width: 480)
        .task {
            while !Task.isCancelled {
                status.refresh()
                controller.refreshPolisherAvailability()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Why Apple Intelligence isn't ready, if it isn't.
    private var polishNote: String? {
        if case .unavailable(let reason) = controller.polisherAvailability { return reason + "." }
        return nil
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

private struct SetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }
}

private struct SetupRow: View {
    let symbol: String
    let title: String
    let detail: String
    var note: String?
    let done: Bool
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
                if let note, !done {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
        window.title = "Welcome to Speak"
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
