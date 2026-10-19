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

        Window("About Dejima", id: AboutView.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
