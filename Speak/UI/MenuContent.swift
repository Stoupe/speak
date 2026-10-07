import SpeakCore
import SwiftUI

struct MenuContent: View {
    let controller: DictationController
    @AppStorage(Preferences.polishEnabled) private var polishEnabled = true
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        statusSection

        if !controller.history.items.isEmpty {
            Divider()
            Section("Recent — click to copy") {
                ForEach(controller.history.items.prefix(5)) { item in
                    Button(preview(item.text)) { controller.copy(item) }
                }
            }
            Button("Paste Last Dictation") { controller.pasteLast() }
                .keyboardShortcut("v", modifiers: [.command, .option])
        }

        Divider()
        Toggle("Polish Text", isOn: $polishEnabled)
        if polishEnabled, case .unavailable(let reason) = controller.polisherAvailability {
            Text(reason)
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Speak") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusSection: some View {
        switch controller.status {
        case .needsAccessibility:
            Button("Grant Accessibility Access…") { controller.openAccessibilitySettings() }
        case .needsMicrophone:
            Button("Grant Microphone Access…") { controller.openMicrophoneSettings() }
        default:
            Text(controller.statusMessage)
        }
    }

    private func preview(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }
}
