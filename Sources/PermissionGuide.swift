import AppKit
import SwiftUI

/// Walks someone through granting Accessibility access.
///
/// The system's own prompt appears once, says almost nothing, and drops you in
/// a settings pane where the app you need is often not listed at all — you're
/// expected to find it yourself with the `+` button. People routinely add the
/// wrong thing there: an alias, a second copy still sitting in Downloads, or
/// the Xcode build instead of the one in Applications. The grant is bound to a
/// specific bundle, so the wrong entry silently does nothing.
///
/// This window floats above System Settings and offers the *running* bundle as
/// a draggable icon, so whatever lands in the list is by construction the
/// binary that needs the permission.
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var watcher: Task<Void, Never>?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        if !panel.isVisible {
            panel.center()
        }
        // An agent app has no Dock icon to click, so bring it up explicitly or
        // the window opens behind whatever is in front.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        startWatching()
    }

    func close() {
        stopWatching()
        panel?.orderOut(nil)
    }

    static let windowWidth: CGFloat = 420

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: PermissionGuideView(
            appURL: Bundle.main.bundleURL,
            openSettings: Self.openAccessibilitySettings
        ))
        // Height comes from the content — the warning about running outside
        // Applications is only sometimes there, and a fixed height would leave
        // a hole in the common case.
        host.frame.size = CGSize(width: Self.windowWidth, height: host.fittingSize.height)

        let panel = NSPanel(contentRect: host.frame,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered,
                            defer: false)
        panel.title = String(localized: "Accessibility access")
        panel.isFloatingPanel = true
        // Above System Settings, which is where the drop target lives.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = host
        return panel
    }

    // MARK: - Watching for the grant

    /// There is no notification for this, so poll. It costs nothing and only
    /// runs while the window is open.
    private func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                if AXIsProcessTrusted() {
                    self.close()
                    self.onGranted()
                    return
                }
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopWatching()
    }
}

private struct PermissionGuideView: View {
    let appURL: URL
    let openSettings: () -> Void

    /// A grant follows the bundle. Granting one that lives in Downloads or in
    /// a DerivedData folder works right up until the app moves, at which point
    /// it silently stops — worth saying before it happens.
    private var isInApplications: Bool {
        // Covers ~/Applications too, which is just as stable a home.
        appURL.path.contains("/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Let Dejima see ⌘C")
                    .font(.headline)
                Text("macOS won't let any app watch the keyboard without permission. Dejima only ever looks for two ⌘C presses in a row.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(1, "Open the Accessibility list.") {
                Button("Open Accessibility Settings", action: openSettings)
            }

            step(2, "Drag Dejima into that list, then switch it on.") {
                icon
            }

            if !isInApplications {
                Label {
                    Text("Dejima is running from \(appURL.deletingLastPathComponent().path). The permission is tied to this exact location — move it to Applications first, or you'll have to grant it again.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("This window closes by itself once the switch is on.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: PermissionGuide.windowWidth, alignment: .topLeading)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                control()
            }
        }
    }

    /// The running bundle itself, so there is nothing to pick wrongly.
    private var icon: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(appURL.lastPathComponent)
                    .font(.callout.weight(.medium))
                Text("Drag me")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        // A file URL, not the file's contents: an .app is a directory, and the
        // list in System Settings wants a reference to it the same way Finder
        // hands one over.
        .onDrag { NSItemProvider(object: appURL as NSURL) }
    }
}

#Preview("In Applications") {
    PermissionGuideView(appURL: URL(fileURLWithPath: "/Applications/Dejima.app"),
                        openSettings: {})
}

#Preview("Somewhere else") {
    PermissionGuideView(appURL: URL(fileURLWithPath: "/Users/you/Downloads/Dejima.app"),
                        openSettings: {})
}
