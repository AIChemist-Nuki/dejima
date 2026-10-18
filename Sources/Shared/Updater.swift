import AppKit
import Combine
import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var checksAutomatically = false
    @Published private(set) var updateAvailable = false

    private var updaterController: SPUStandardUpdaterController!

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$checksAutomatically)
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

    func feedURLString(for updater: SPUUpdater) -> String? {
        let variant: String
        if #available(macOS 26, *) {
            variant = "macos26"
        } else {
            variant = "macos15"
        }
        return "https://github.com/AIChemist-Nuki/dejima/releases/latest/download/appcast-\(variant).xml"
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
