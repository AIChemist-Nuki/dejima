// The App Store delivers its own updates and doesn't allow in-app updaters.
#if !APP_STORE
import AppKit
import Sparkle

@MainActor
@Observable
final class Updater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private(set) var canCheckForUpdates = false
    private(set) var checksAutomatically = false
    private(set) var updateAvailable = false

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController!
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        // KVO callbacks aren't guaranteed to arrive on the main actor.
        let updater = updaterController.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.checksAutomatically = value }
            },
        ]
    }

    func start() {
        let defaults = UserDefaults.standard
        if let previousChoice = defaults.object(forKey: "checkForUpdatesAutomatically") as? Bool {
            if defaults.object(forKey: "SUEnableAutomaticChecks") == nil {
                updaterController.updater.automaticallyChecksForUpdates = previousChoice
            }
            defaults.removeObject(forKey: "checkForUpdatesAutomatically")
            defaults.removeObject(forKey: "lastUpdateCheck")
        }
        updaterController.startUpdater()
    }

    func setChecksAutomatically(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func checkNow() {
        NSApp.activate()
        updaterController.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        updateAvailable = !handleShowingUpdate
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }
}
#endif
