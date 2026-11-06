import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let controller: DictationController
    @Bindable var updater: Updater
    @Bindable private var telemetry: Telemetry

    @AppStorage(Preferences.microphoneUID) private var microphoneUID = ""
    @AppStorage(Preferences.triggerKey) private var triggerKey = TriggerKey.fn
    @AppStorage(Preferences.polishEnabled) private var polishEnabled = true
    @AppStorage(Preferences.soundsEnabled) private var soundsEnabled = true
    @AppStorage(Preferences.trailingSpace) private var trailingSpace = true
    @AppStorage(Preferences.dictionary) private var dictionary = ""
    @State private var microphones: [AudioDevices.Device] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(controller: DictationController, updater: Updater) {
        self.controller = controller
        self.updater = updater
        telemetry = controller.telemetry
    }

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

            if controller.telemetry.isAvailable {
                Section {
                    Toggle(UsageStatsCopy.toggle, isOn: $telemetry.isEnabled)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One anonymous summary a day. Never what you say.")
                            .foregroundStyle(.secondary)
                        UsageStatsLinks(telemetry: controller.telemetry)
                            .font(.footnote)
                    }
                }
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
        .frame(width: 440, height: height)
        .onAppear {
            updater.refresh()
            microphones = AudioDevices.inputDevices()
            controller.refreshPolisherAvailability()
        }
    }

    /// The form doesn't scroll, so the window is sized to fit it: rows that only some builds show add their height.
    private var height: CGFloat {
        #if DEBUG
        if let height = Self.snapshotHeight { return height }
        #endif
        return 655 + (updater.isEnabled ? 28 : 0) + (controller.telemetry.isAvailable ? Self.usageStatsHeight : 0)
    }

    /// The usage stats section, measured with `-snapshot` (see `Snapshot.swift`).
    static let usageStatsHeight: CGFloat = 110

    #if DEBUG
    /// Set by `-snapshot` to render the form without the fixed height, so it can be measured.
    static var snapshotHeight: CGFloat?
    #endif

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
