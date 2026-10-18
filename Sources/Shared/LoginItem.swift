import Foundation
import ServiceManagement

/// Registers the main app as a login item without a helper bundle.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The menu reads system status again after registration attempts.
            NSLog("Dejima: could not \(enabled ? "register" : "unregister") the login item: \(error.localizedDescription)")
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
