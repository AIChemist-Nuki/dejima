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
/// It offers the *running* bundle as a draggable icon, so whatever lands in
/// the list is by construction the binary that needs the permission. Once
/// System Settings is open, the guide steps aside and a strip docks onto the
/// bottom of the Settings window instead, holding the same icon right under
/// the list it has to go into.
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var dock: NSPanel?
    private var watcher: Task<Void, Never>?
    /// The dock's back button brings the guide back while Settings stays open.
    /// Opening Settings from the guide again undoes it.
    private var dockDismissed = false
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
        dockDismissed = false
        // An agent app has no Dock icon to click, so bring it up explicitly or
        // the window opens behind whatever is in front.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        startWatching()
    }

    func close() {
        stopWatching()
        panel?.orderOut(nil)
        dock?.orderOut(nil)
    }

    private func openSettings() {
        dockDismissed = false
        Self.openAccessibilitySettings()
    }

    static let windowWidth: CGFloat = 420

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: PermissionGuideView(
            appURL: Bundle.main.bundleURL,
            openSettings: { [weak self] in self?.openSettings() }
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

    /// Borderless and non-activating: clicking or dragging from it must not
    /// pull focus away from System Settings, or the Settings window would drop
    /// behind whatever was in front of it.
    private func makeDock() -> NSPanel {
        let host = NSHostingView(rootView: SettingsDockView(
            appURL: Bundle.main.bundleURL,
            back: { [weak self] in self?.dismissDock() }
        ))
        host.frame.size = host.fittingSize

        let dock = NSPanel(contentRect: host.frame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        dock.isFloatingPanel = true
        dock.level = .floating
        dock.hidesOnDeactivate = false
        dock.becomesKeyOnlyIfNeeded = true
        dock.isReleasedWhenClosed = false
        dock.isOpaque = false
        dock.backgroundColor = .clear
        dock.hasShadow = true
        dock.contentView = host
        return dock
    }

    private func dismissDock() {
        dockDismissed = true
        dock?.orderOut(nil)
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Watching for the grant

    /// There is no notification for the grant, nor for another app's window
    /// moving, so poll both. It only runs while the guide is up.
    private func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                // Fast enough for the dock to keep up with a dragged window.
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                tick += 1
                if tick % 8 == 0, AXIsProcessTrusted() {
                    self.close()
                    self.onGranted()
                    return
                }
                self.followSettings()
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    /// Settings on screen: the dock rides along its bottom edge and the guide
    /// gets out of the way. Settings gone: the guide comes back, since it is
    /// the only way left to reopen it.
    private func followSettings() {
        guard let panel else { return }
        let settings = SystemSettings.frontWindowFrame()

        guard let settings, !dockDismissed else {
            dock?.orderOut(nil)
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        if panel.isVisible { panel.orderOut(nil) }

        // The dock floats, so it would hang over any app someone switches to.
        // Only show it while Settings (or the dock itself) is what's in use.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == SystemSettings.bundleID || front == Bundle.main.bundleIdentifier else {
            dock?.orderOut(nil)
            return
        }

        if dock == nil { dock = makeDock() }
        guard let dock else { return }
        // Starts a little inside the sidebar and ends just short of the right
        // edge, so it reads as belonging to the pane rather than the window.
        let minX = settings.minX + Self.dockSidebarInset
        let frame = CGRect(x: minX,
                           y: settings.minY + 16,
                           width: settings.maxX - 8 - minX,
                           height: dock.frame.height)
        if dock.frame != frame { dock.setFrame(frame, display: true) }
        if !dock.isVisible { dock.orderFrontRegardless() }
    }

    /// Roughly where System Settings' sidebar ends.
    private static let dockSidebarInset: CGFloat = 190

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        dock?.orderOut(nil)
    }
}

private enum SystemSettings {
    static let bundleID = "com.apple.systempreferences"

    /// The frontmost System Settings window in AppKit screen coordinates, or
    /// nil when none is on screen — closed, minimised or on another Space.
    ///
    /// Window bounds and owners are readable without Screen Recording; only
    /// titles are not, and nothing here needs them.
    static func frontWindowFrame() -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first
        else { return nil }

        // Front to back, so the first normal-level match is the one in use.
        for info in windows {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  // Skips sheets and popovers Settings puts up on the same level.
                  bounds.height > 200
            else { continue }
            // Quartz measures from the top of the primary screen, AppKit from
            // its bottom.
            return CGRect(x: bounds.minX,
                          y: primary.frame.maxY - bounds.maxY,
                          width: bounds.width,
                          height: bounds.height)
        }
        return nil
    }
}

/// The strip docked onto System Settings: an arrow pointing up at the list,
/// and the app itself to drag there.
private struct SettingsDockView: View {
    let appURL: URL
    let back: () -> Void

    private var appName: String { appURL.deletingPathExtension().lastPathComponent }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to the guide")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.blue)
                    Text("Drag **\(appName)** to the list above to allow **Accessibility**")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text(appName)
                        .font(.body)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
                .overlay(BundleDragSource(url: appURL))
            }
        }
        .padding(14)
        .frame(minWidth: 480, maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator))
    }
}

/// Starts a file drag of the bundle straight from AppKit. The dock is never
/// key, and SwiftUI's `onDrag` can't be relied on to see the first click in a
/// window that isn't; `acceptsFirstMouse` makes the very first press count.
private struct BundleDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> DragView { DragView(url: url) }
    func updateNSView(_ view: DragView, context: Context) { view.url = url }

    final class DragView: NSView, NSDraggingSource {
        var url: URL

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Swallowed so the drags that follow come here.
        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            // A file URL, the way Finder hands an .app over.
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
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

#Preview("Docked on Settings") {
    SettingsDockView(appURL: URL(fileURLWithPath: "/Applications/Dejima.app"), back: {})
        .padding()
}
