import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: Controller
    @State private var primary = LanguageRouter.primary
    @State private var secondary = LanguageRouter.secondary
    @AppStorage("polishWithAppleIntelligence") private var polish = false

    var body: some View {
        if !controller.hasAccessibility {
            Button("Grant Accessibility access…") { controller.requestPermission() }
            Divider()
        }

        Button(controller.isMonitoring ? "Pause ⌘C ⌘C" : "Resume ⌘C ⌘C") {
            controller.toggleMonitoring()
        }
        .disabled(!controller.hasAccessibility)

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
