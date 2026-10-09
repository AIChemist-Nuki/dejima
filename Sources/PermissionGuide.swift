import AppKit
import SwiftUI

/// Guides Accessibility setup using the running app bundle as the drag source.
/// A separate panel follows System Settings while its window is visible.
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var dock: NSPanel?
    private var watcher: Task<Void, Never>?
    /// Keep the guide visible after Back, until Settings is opened from it again.
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
        // Activate the agent app so the guide opens in front.
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
        // The installation-location warning changes the required height.
        host.frame.size = CGSize(width: Self.windowWidth, height: host.fittingSize.height)

        let panel = NSPanel(contentRect: host.frame,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered,
                            defer: false)
        panel.title = String(localized: "Accessibility access")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = host
        return panel
    }

    /// Keep System Settings active while the user drags the app into its list.
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

    /// Poll permission and Settings geometry only while the guide is open.
    private func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
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

    /// Show the guide when the Settings window is unavailable or the dock is dismissed.
    private func followSettings() {
        guard let panel else { return }
        let settings = SystemSettings.frontWindowFrame()

        guard let settings, !dockDismissed else {
            dock?.orderOut(nil)
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        if panel.isVisible { panel.orderOut(nil) }

        // Hide the floating dock when another app is active.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == SystemSettings.bundleID || front == Bundle.main.bundleIdentifier else {
            dock?.orderOut(nil)
            return
        }

        if dock == nil { dock = makeDock() }
        guard let dock else { return }
        let minX = settings.minX + Self.dockSidebarInset
        let frame = CGRect(x: minX,
                           y: settings.minY + 16,
                           width: settings.maxX - 8 - minX,
                           height: dock.frame.height)
        if dock.frame != frame { dock.setFrame(frame, display: true) }
        if !dock.isVisible { dock.orderFrontRegardless() }
    }

    /// Approximate width of the System Settings sidebar.
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

    /// Returns the frontmost visible Settings window in AppKit coordinates.
    /// Window bounds and owners are available without Screen Recording access.
    static func frontWindowFrame() -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first
        else { return nil }

        // Window information is ordered front to back.
        for info in windows {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  // Exclude small sheets and popovers at the same window level.
                  bounds.height > 200
            else { continue }
            // Convert from Quartz top-left coordinates to AppKit bottom-left coordinates.
            return CGRect(x: bounds.minX,
                          y: primary.frame.maxY - bounds.maxY,
                          width: bounds.width,
                          height: bounds.height)
        }
        return nil
    }
}

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

/// Use AppKit's acceptsFirstMouse so a drag can begin in the non-key dock.
/// SwiftUI's onDrag may miss that first press.
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

        // Handle the initial press to receive subsequent drag events.
        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
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

    /// Warn before granting access to an app that may be moved after installation.
    private var isInApplications: Bool {
        // Includes both system-wide and per-user Applications directories.
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
        // System Settings expects the app bundle URL as the drag payload.
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
