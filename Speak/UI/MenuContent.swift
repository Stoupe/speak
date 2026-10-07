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
            Section("Recent — click to copy, ⌥ for original") {
                ForEach(controller.history.items.prefix(5)) { item in
                    Button(preview(item.text)) { controller.copy(item.text) }
                        .modifierKeyAlternate(.option) {
                            Button(preview(item.raw)) { controller.copy(item.raw) }
                        }
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
            openSettings()
            // A menu bar app isn't active, so the window would open behind the frontmost app.
            DispatchQueue.main.async {
                NSApp.activate()
                NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?
                    .orderFrontRegardless()
            }
        }
        .keyboardShortcut(",")
        Divider()
        Button("About Speak") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Dictation that stays on your Mac.",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
            ])
        }
        Button("Quit Speak") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusSection: some View {
        switch controller.status {
        case .needsAccessibility, .needsMicrophone:
            Button("Finish Setting Up Speak…") { controller.showSetup() }
        default:
            Text(controller.statusMessage)
        }
    }

    private func preview(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }
}
