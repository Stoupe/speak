import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let controller: DictationController
    @Bindable var updater: Updater

    @AppStorage(Preferences.microphoneUID) private var microphoneUID = ""
    @AppStorage(Preferences.triggerKey) private var triggerKey = TriggerKey.fn
    @AppStorage(Preferences.polishEnabled) private var polishEnabled = true
    @AppStorage(Preferences.soundsEnabled) private var soundsEnabled = true
    @AppStorage(Preferences.trailingSpace) private var trailingSpace = true
    @AppStorage(Preferences.dictionary) private var dictionary = ""
    @State private var microphones: [AudioDevices.Device] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Trigger key", selection: $triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.menuTitle).tag($0) }
                }
                Picker("Microphone", selection: $microphoneUID) {
                    Text("System Default").tag("")
                    ForEach(microphones) { Text($0.name).tag($0.uid) }
                }
                Toggle("Polish text", isOn: $polishEnabled)
                Toggle("Add space after dictation", isOn: $trailingSpace)
                Toggle("Sounds", isOn: $soundsEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if updater.isEnabled {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                }
            } footer: {
                Text("Hold \(triggerKey.name) to dictate, or double-tap it for hands-free. Esc cancels.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $dictionary)
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Dictionary")
            } footer: {
                Text("Names and terms to spell exactly, one per line.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Speech model", value: modelDescription)
                LabeledContent("Polishing", value: polishDescription)
                if !controller.history.items.isEmpty {
                    Button("Clear History", role: .destructive) { controller.clearHistory() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // One row shorter in local builds, which have no update setting.
        .frame(width: 440, height: updater.isEnabled ? 683 : 655)
        .onAppear {
            updater.refresh()
            microphones = AudioDevices.inputDevices()
            controller.refreshPolisherAvailability()
        }
    }

    private var modelDescription: String {
        switch controller.modelState {
        case .loading: "Loading…"
        case .ready: "On-device, ready"
        case .failed(let message): message
        }
    }

    private var polishDescription: String {
        switch controller.polisherAvailability {
        case .available: "Apple Intelligence, on-device"
        case .unavailable(let reason): reason
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
