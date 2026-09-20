import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: Controller
    @State private var primary = LanguageRouter.primary
    @State private var secondary = LanguageRouter.secondary
    @AppStorage("polishWithAppleIntelligence") private var polish = false
    /// Mirrors the Service Management status, which is the real source of
    /// truth — the system can revoke this from Login Items at any time.
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var autoUpdate = Updater.checksAutomatically

    var body: some View {
        if !controller.hasAccessibility {
            Button("Grant Accessibility access…") { controller.requestPermission() }
            Divider()
        }

        // Two separate literals rather than a ternary, so both reach the
        // String Catalog.
        if controller.isMonitoring {
            Button("Pause ⌘C ⌘C") { controller.toggleMonitoring() }
                .disabled(!controller.hasAccessibility)
        } else {
            Button("Resume ⌘C ⌘C") { controller.toggleMonitoring() }
                .disabled(!controller.hasAccessibility)
        }

        Divider()

        Picker("Translate into", selection: $primary) {
            ForEach(LanguageRouter.choices, id: \.self) { code in
                Text(LanguageRouter.displayName(code)).tag(code)
            }
        }
        .onChange(of: primary) { _, new in LanguageRouter.primary = new }

        Picker("Unless it already is, then", selection: $secondary) {
            ForEach(LanguageRouter.choices, id: \.self) { code in
                Text(LanguageRouter.displayName(code)).tag(code)
            }
        }
        .onChange(of: secondary) { _, new in LanguageRouter.secondary = new }

        if Polisher.isAvailable {
            Toggle("Refine with Apple Intelligence", isOn: $polish)
        }

        Divider()

        Toggle("Open at login", isOn: Binding(
            get: { launchAtLogin },
            set: { wanted in
                LoginItem.setEnabled(wanted)
                launchAtLogin = LoginItem.isEnabled
            }
        ))

        if LoginItem.needsApproval {
            Button("Approve in Login Items…") { LoginItem.openSettings() }
        }

        Toggle("Check for updates automatically", isOn: $autoUpdate)
            .onChange(of: autoUpdate) { _, on in Updater.checksAutomatically = on }

        Divider()

        Button("Check for updates…") { Updater.checkNow() }
        Button("Check language models…") { openTranslationSettings() }
        Button("Quit Dejima") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Apple's models are downloaded per language pair and shared system-wide,
    /// so send people to the one place that manages them.
    private func openTranslationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
