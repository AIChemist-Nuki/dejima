import SwiftUI

@main
struct KotobaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: delegate.controller)
        } label: {
            Image(systemName: "character.bubble")
        }
        .menuBarExtraStyle(.menu)
    }
}
