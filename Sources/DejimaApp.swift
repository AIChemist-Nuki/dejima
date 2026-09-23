import SwiftUI

@main
struct DejimaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: delegate.controller)
        } label: {
            Image(nsImage: DejimaMark.menuBarImage())
        }
        .menuBarExtraStyle(.menu)
    }
}
