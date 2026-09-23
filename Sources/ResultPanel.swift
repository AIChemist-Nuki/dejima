import AppKit
import SwiftUI

@MainActor
final class ResultModel: ObservableObject {
    enum State {
        case translating
        /// Some chunks are in, the rest are still coming.
        case streaming(String)
        /// Fully translated; the refiner is having a second pass at it.
        case refining(String)
        case done(String)
        case failed(String)
    }

    @Published var sourceText = ""
    @Published var state: State = .translating
    @Published var routeLabel = ""
    /// A pinned panel ignores clicks outside itself and stays where it is when
    /// the next translation arrives.
    @Published var isPinned = false

    /// Text worth putting on the pasteboard: a finished translation, or the
    /// draft while the refiner works on it. A half-streamed result is left out
    /// — copying it would silently hand over a truncated translation.
    var copyableText: String? {
        switch state {
        case .done(let text), .refining(let text):
            return text
        case .translating, .streaming, .failed:
            return nil
        }
    }

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

    func stream(_ text: String) { state = .streaming(text) }

    func beginRefining() {
        if case .streaming(let text) = state { state = .refining(text) }
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
    private let model: ResultModel
    private var dismissMonitor: Any?

    /// Where the pointer was when the panel was last shown. The panel hangs off
    /// this point, so it has to survive the resizes that follow.
    private var anchor: NSPoint = .zero

    init(model: ResultModel) {
        self.model = model
        let initial = CGSize(width: ResultView.Layout.width, height: ResultView.Layout.minHeight)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: initial),
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
        // No traffic light. The close button landed right on top of the
        // language badge, and hiding only that one left minimise and zoom
        // behind as two dim circles that did nothing — a utility panel can be
        // neither minimised nor zoomed. The header carries its own close
        // button, which a pinned panel needs anyway now that clicking away no
        // longer dismisses it.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.contentView = NSHostingView(rootView: ResultView(
            model: model,
            onContentHeightChange: { [weak self] height in self?.fit(contentHeight: height) },
            onClose: { [weak self] in self?.hide() }
        ))
    }

    func show(near point: NSPoint) {
        // A pinned panel was put somewhere on purpose; leave it there.
        if !model.isPinned {
            anchor = point
            place(height: panel.frame.height)
        }
        panel.orderFrontRegardless()
        installDismissMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitor()
        // Pinning applies to the result you pinned. Keeping it on would make
        // the next translation appear at the old spot for no clear reason.
        model.isPinned = false
    }

    // MARK: - Geometry

    /// Matches the window to the height its content actually wants.
    private func fit(contentHeight: CGFloat) {
        let target = ResultView.Layout.height(forContent: contentHeight)
        guard abs(target - panel.frame.height) > 0.5 else { return }

        guard model.isPinned else {
            place(height: target)
            return
        }
        // Pinned: the panel may have been dragged deliberately, so grow from
        // where it stands rather than snapping back to the pointer.
        var frame = panel.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true)
    }

    /// Hangs the panel below and right of the anchor at the given height,
    /// nudged as needed to keep all of it on the screen the pointer is on.
    private func place(height: CGFloat) {
        let width = ResultView.Layout.width
        var origin = NSPoint(x: anchor.x + 12, y: anchor.y - 12 - height)

        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(origin.x, visible.maxX - width - 8)
            origin.x = max(origin.x, visible.minX + 8)
            origin.y = min(origin.y, visible.maxY - height - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
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
                    if event.keyCode == 53 { self.hide() }  // esc closes either way
                } else if !self.model.isPinned {
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
