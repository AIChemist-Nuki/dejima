import AppKit
import SwiftUI

@MainActor
final class ResultModel: ObservableObject {
    enum State {
        case translating
        case done(String)
        case failed(String)
    }

    @Published var sourceText = ""
    @Published var state: State = .translating
    @Published var routeLabel = ""

    func begin(source: String, route: Route?) {
        sourceText = source
        state = .translating
        if let route {
            let to = LanguageRouter.displayName(route.target)
            // With no detected source the framework picks one, so naming a
            // source here would be a guess. Just show where it's going.
            routeLabel = route.source.map { "\(LanguageRouter.displayName($0)) → \(to)" } ?? "→ \(to)"
        } else {
            routeLabel = ""
        }
    }

    func succeed(_ text: String) { state = .done(text) }

    func fail(_ error: Error) {
        state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}

/// Floating panel that appears next to the pointer.
///
/// `.nonactivatingPanel` is the important flag: the panel can show itself
/// without pulling focus away from whatever you were reading, so the caret
/// stays where it was.
@MainActor
final class ResultPanel {
    private let panel: NSPanel
    private var dismissMonitor: Any?

    private let size = CGSize(width: 380, height: 240)

    init(model: ResultModel) {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered,
                        defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ResultView(model: model))
    }

    func show(near point: NSPoint) {
        panel.setFrameTopLeftPoint(clamp(point))
        panel.orderFrontRegardless()
        installDismissMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitor()
    }

    /// Keep the whole panel inside the screen the pointer is on.
    private func clamp(_ point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return point }

        var origin = NSPoint(x: point.x + 12, y: point.y - 12)
        origin.x = min(origin.x, visible.maxX - size.width - 8)
        origin.x = max(origin.x, visible.minX + 8)
        origin.y = max(origin.y, visible.minY + size.height + 8)
        origin.y = min(origin.y, visible.maxY - 8)
        return origin
    }

    // MARK: - Dismissal

    private func installDismissMonitor() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.hide() }  // esc
                } else {
                    self.hide()
                }
            }
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }
}
