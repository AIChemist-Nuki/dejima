import AppKit
import SwiftUI

@MainActor
@Observable
final class ResultModel {
    enum State {
        case translating
        case streaming(String)
        case refining(String)
        case done(String)
        case failed(String)
        case feedback(SelectionFeedback.Prompt)
    }

    var sourceText = ""
    var state: State = .translating
    var routeLabel = ""
    /// Pinned panels retain their position and ignore outside clicks.
    var isPinned = false

    /// Only complete translations can be copied, including drafts being refined.
    var copyableText: String? {
        switch state {
        case .done(let text), .refining(let text):
            return text
        case .translating, .streaming, .failed, .feedback:
            return nil
        }
    }

    func begin(source: String, route: Route?) {
        sourceText = source
        state = .translating
        if let route {
            let to = LanguageRouter.displayName(route.target)
            // Omit the source label when language detection is delegated to the hub.
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

    func showFeedback(_ prompt: SelectionFeedback.Prompt) {
        sourceText = ""
        routeLabel = ""
        state = .feedback(prompt)
    }
}

/// Displays results without activating the app or moving the text caret.
@MainActor
final class ResultPanel {
    private let panel: NSPanel
    private let model: ResultModel
    private var dismissMonitor: Any?

    /// Retain the initial pointer position while streaming results resize the panel.
    private var anchor: NSPoint = .zero
    /// The selected text to keep uncovered, or nil to follow the pointer.
    private var selection: NSRect?
    /// Chosen once per result so streaming growth doesn't flip the panel across the selection.
    private var placesBelowSelection = true
    /// The frame last set by `place`; a different origin means the user dragged the panel.
    private var placedFrame: NSRect = .zero

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
        // Use the header's close button and hide the unused utility-window controls.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.contentView = NSHostingView(rootView: ResultView(
            model: model,
            onContentHeightChange: { [weak self] height in self?.fit(contentHeight: height) },
            onClose: { [weak self] in self?.hide() }
        ))
    }

    func show(near point: NSPoint, avoiding selection: NSRect? = nil) {
        if !model.isPinned {
            anchor = point
            chooseSide(for: selection)
            place(height: panel.frame.height)
        }
        panel.orderFrontRegardless()
        installDismissMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeDismissMonitor()
        // Closing the panel resets pinning for the next result.
        model.isPinned = false
    }

    // MARK: - Geometry

    private func fit(contentHeight: CGFloat) {
        let target = ResultView.Layout.height(forContent: contentHeight)
        guard abs(target - panel.frame.height) > 0.5 else { return }

        guard model.isPinned || panel.frame.origin != placedFrame.origin else {
            place(height: target)
            return
        }
        // Keep the top edge of a pinned or dragged panel fixed when resizing.
        var frame = panel.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true)
    }

    private static let gap: CGFloat = 8

    /// Prefer the space below the selection, as Look Up does, unless more room is above.
    /// Selections too tall to leave room on either side fall back to the pointer.
    private func chooseSide(for selection: NSRect?) {
        self.selection = nil
        // Ignore bounds that don't land on a screen; some apps report bogus coordinates.
        guard let selection,
              let visible = NSScreen.screens.first(where: {
                  $0.frame.contains(NSPoint(x: selection.midX, y: selection.midY))
              })?.visibleFrame
        else { return }

        let below = selection.minY - visible.minY - Self.gap * 2
        let above = visible.maxY - selection.maxY - Self.gap * 2
        guard max(below, above) >= ResultView.Layout.minHeight else { return }
        self.selection = selection
        placesBelowSelection = below >= ResultView.Layout.maxHeight || below >= above
    }

    /// Place the panel beside the selection or pointer, constrained to that screen's visible area.
    private func place(height: CGFloat) {
        let width = ResultView.Layout.width
        var origin: NSPoint
        let screen: NSScreen?
        if let selection {
            origin = NSPoint(x: selection.minX,
                             y: placesBelowSelection ? selection.minY - Self.gap - height : selection.maxY + Self.gap)
            screen = self.screen(containing: NSPoint(x: selection.midX, y: selection.midY))
        } else {
            origin = NSPoint(x: anchor.x + 12, y: anchor.y - 12 - height)
            screen = self.screen(containing: anchor)
        }

        if let visible = screen?.visibleFrame {
            origin.x = min(origin.x, visible.maxX - width - 8)
            origin.x = max(origin.x, visible.minX + 8)
            origin.y = min(origin.y, visible.maxY - height - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        placedFrame = panel.frame
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
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
                    if event.keyCode == 53 { self.hide() }  // Escape also dismisses pinned panels.
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
