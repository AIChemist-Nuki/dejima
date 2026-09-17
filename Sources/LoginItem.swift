import Foundation
import ServiceManagement

/// Launch at login, registered as the main app rather than a helper.
///
/// There is no helper bundle to install: Dejima is already an agent with no
/// Dock icon, so the thing that should start at login is the app itself.
///
/// Registration is bound to the code signature. An ad-hoc signed build will
/// lose this the same way it loses the Accessibility grant, and macOS only
/// honours it for an app in a stable location — build to /Applications if you
/// want it to stick.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but waiting for the user to switch it on in Login Items.
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
            // A menu item has nowhere useful to report this. The menu reads the
            // real status back, so a failure simply shows as still-off.
            NSLog("Dejima: could not \(enabled ? "register" : "unregister") the login item: \(error.localizedDescription)")
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
