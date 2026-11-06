import SwiftUI

@main
struct SpeakApp: App {
    @State private var controller: DictationController
    @State private var updater = Updater()

    init() {
        Preferences.registerDefaults()
        #if DEBUG
        if let directory = Snapshot.requestedDirectory {
            let controller = Snapshot.makeController()
            _controller = State(initialValue: controller)
            Task { await Snapshot.run(controller: controller, to: directory) }
            return
        }
        #endif
        let controller = DictationController()
        controller.launch()
        _controller = State(initialValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller, updater: updater)
        } label: {
            Image(controller.isRecording ? "MenuBarIconRecording" : "MenuBarIcon")
        }

        Settings {
            SettingsView(controller: controller, updater: updater)
        }
        .windowResizability(.contentSize)
    }
}
