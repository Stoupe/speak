import SpeakCore
import SwiftUI

struct MenuContent: View {
    let controller: DictationController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        statusSection

        if !controller.history.items.isEmpty {
            Divider()
            // Click copies; holding ⌥ swaps in the unpolished original.
            Section("Recent") {
                ForEach(controller.history.items.prefix(5)) { item in
                    Button { controller.copy(item.text) } label: {
                        Label(preview(item.text), systemImage: "doc.on.doc")
                    }
                    .modifierKeyAlternate(.option) {
                        Button { controller.copy(item.raw) } label: {
                            Label(preview(item.raw), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }

        Divider()
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
