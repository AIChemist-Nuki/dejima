import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: Controller
    @State private var primary = LanguageRouter.primary
    @State private var secondary = LanguageRouter.secondary
    @AppStorage("polishWithAppleIntelligence") private var polish = false
    /// Read system status because login registration can change outside the app.
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var autoUpdate = Updater.checksAutomatically

    var body: some View {
        if !controller.hasAccessibility {
            Button("Grant Accessibility access…") { controller.requestPermission() }
            Divider()
        }

        // Keep separate literals so both labels are extracted into the String Catalog.
        if controller.isMonitoring {
            Button {
                controller.toggleMonitoring()
            } label: {
                Text(hinted(String(localized: "Pause 「Dejima」"), "⌘C C"))
            }
            .disabled(!controller.hasAccessibility)
        } else {
            Button {
                controller.toggleMonitoring()
            } label: {
                Text(hinted(String(localized: "Resume 「Dejima」"), "⌘C C"))
            }
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

    /// Display the double-copy gesture inline; keyboardShortcut cannot express it
    /// and registering ⌘C would intercept copy while the menu is open.
    private func hinted(_ title: String, _ shortcut: String) -> AttributedString {
        // Match the menu font instead of the default attributed-string size.
        let size = NSFont.menuFont(ofSize: 0).pointSize
        var text = AttributedString(title)
        text.font = .system(size: size)
        var hint = AttributedString("  \(shortcut)")
        hint.font = .system(size: size)
        hint.foregroundColor = Color(nsColor: .tertiaryLabelColor)
        text.append(hint)
        return text
    }

    /// Language models are managed system-wide in Language & Region settings.
    private func openTranslationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
