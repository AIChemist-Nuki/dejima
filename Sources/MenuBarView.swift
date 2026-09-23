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

    /// Puts a dimmed hint after a menu title, matched to the size and grey of
    /// the key equivalents down the right-hand side.
    ///
    /// It can't be one of those. macOS reserves that column for real single
    /// shortcuts, and ⌘C ⌘C is a double press the app watches for globally —
    /// `.keyboardShortcut` can't express it, and asking for plain ⌘C would
    /// both claim that key from the open menu and describe the wrong gesture.
    /// So the hint sits inline, and only has to not look out of place.
    private func hinted(_ title: String, _ shortcut: String) -> AttributedString {
        // Left to itself the hint comes out at the ordinary system size,
        // visibly smaller than the menu around it.
        let size = NSFont.menuFont(ofSize: 0).pointSize
        var text = AttributedString(title)
        text.font = .system(size: size)
        var hint = AttributedString("  \(shortcut)")
        hint.font = .system(size: size)
        // .secondary is a good deal darker than a key equivalent.
        hint.foregroundColor = Color(nsColor: .tertiaryLabelColor)
        text.append(hint)
        return text
    }

    /// Apple's models are downloaded per language pair and shared system-wide,
    /// so send people to the one place that manages them.
    private func openTranslationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
