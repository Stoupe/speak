import SwiftUI

@main
struct SpeakApp: App {
    @State private var controller: DictationController

    init() {
        Preferences.registerDefaults()
        let controller = DictationController()
        controller.launch()
        _controller = State(initialValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(controller.isRecording ? "MenuBarIconRecording" : "MenuBarIcon")
        }

        Settings {
            SettingsView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}
