import Foundation
import Observation
import Sparkle

/// Sparkle updates, only in release builds: `Tools/release.sh` fills in `SUFeedURL` and `SUPublicEDKey`
/// (see `Config/Info.plist`). Xcode and `Tools/install.sh` builds leave them empty and never check, so a dev build
/// is never replaced by a published one (which would also reset its permissions: different certificate).
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// False when an update check is already running.
    private(set) var canCheckForUpdates = false

    /// Mirrors Sparkle's own setting, which it also sets from its "check automatically?" prompt.
    var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    var isEnabled: Bool { controller != nil }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let configured = ["SUFeedURL", "SUPublicEDKey"].allSatisfy { !((info[$0] as? String) ?? "").isEmpty }
        guard configured else {
            controller = nil
            log.info("updates off: no feed URL in this build")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Picks up a change made from Sparkle's prompt.
    func refresh() {
        guard let controller, automaticallyChecks != controller.updater.automaticallyChecksForUpdates else { return }
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }
}
