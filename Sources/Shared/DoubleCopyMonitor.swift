import AppKit

/// Observes double-copy gestures without consuming the copy keystrokes.
/// Global key monitoring requires Accessibility access.
@MainActor
final class DoubleCopyMonitor {
    /// Reports the copied text and, when the source app exposes it, the
    /// selection's bounds in AppKit screen coordinates.
    var onDoubleCopy: ((_ text: String, _ selection: NSRect?) -> Void)?
    /// Reports whether a double copy yielded text, along with the source app.
    /// Copies of non-text content (images, files) are not reported.
    var onReadOutcome: ((_ app: NSRunningApplication?, _ succeeded: Bool) -> Void)?

    /// Maximum interval between copy presses.
    var window: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "doublePressWindow")
        return stored > 0 ? stored : 0.45
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastCopyAt: TimeInterval = -.greatestFiniteMagnitude
    /// Pasteboard change count when the gesture's first copy press was seen.
    private var changeCountAtFirstCopy = 0

    private let keyCodeC: UInt16 = 8

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // Global monitors are silent while our own app is frontmost.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        lastCopyAt = -.greatestFiniteMagnitude
    }

    private func handle(_ event: NSEvent) {
        // Holding ⌘C auto-repeats; that isn't a deliberate double press.
        guard event.keyCode == keyCodeC, !event.isARepeat else { return }
        // Only compare real modifiers so Caps Lock or Fn don't block the gesture.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command else { return }

        let now = event.timestamp
        guard now - lastCopyAt < window else {
            lastCopyAt = now
            changeCountAtFirstCopy = NSPasteboard.general.changeCount
            // Give Chromium/Electron time to build their tree before a fallback read.
            Self.enableAccessibilityTree()
            return
        }

        lastCopyAt = -.greatestFiniteMagnitude
        readPasteboard()
    }

    /// The source app may not have handled the copy event yet. Wait for a
    /// pasteboard change, with a timeout if its contents are unchanged.
    private func readPasteboard(attemptsLeft: Int = 15) {
        let pasteboard = NSPasteboard.general
        let baseline = pasteboard.changeCount
        let firstCopyBaseline = changeCountAtFirstCopy
        let sourceApp = NSWorkspace.shared.frontmostApplication

        Task { [weak self] in
            var remaining = attemptsLeft
            while true {
                try? await Task.sleep(for: .milliseconds(20))
                if pasteboard.changeCount != baseline || remaining == 0 { break }
                remaining -= 1
            }
            guard let self else { return }

            // Neither press reached the pasteboard: copy is disabled or
            // blocked in the source app. Read its live selection instead;
            // the clipboard only holds stale contents.
            let copyFailed = pasteboard.changeCount == firstCopyBaseline
            let text = copyFailed
                ? Self.focusedSelectedText()
                : pasteboard.string(forType: .string)
            if text != nil {
                self.onReadOutcome?(sourceApp, true)
            } else if copyFailed {
                self.onReadOutcome?(sourceApp, false)
            }
            if let text {
                self.onDoubleCopy?(text, Self.focusedSelectionBounds())
            }
        }
    }

    // MARK: - Accessibility fallback

    private static var treeEnabledPIDs: Set<pid_t> = []

    private static func frontmostAppElement() -> (pid: pid_t, element: AXUIElement)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        // Don't stall the main thread on an unresponsive app.
        AXUIElementSetMessagingTimeout(element, 0.25)
        return (pid, element)
    }

    /// Chromium and Electron apps expose their accessibility tree only after a
    /// client asks for it; native apps ignore this attribute.
    private static func enableAccessibilityTree() {
        guard let (pid, app) = frontmostAppElement(), !treeEnabledPIDs.contains(pid) else { return }
        treeEnabledPIDs.insert(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Reads the frontmost app's selected text through Accessibility.
    private static func focusedSelectedText() -> String? {
        guard let (_, app) = frontmostAppElement(),
              let element = copyElement(app, kAXFocusedUIElementAttribute) else { return nil }

        let text = copyString(element, kAXSelectedTextAttribute)
            ?? webSelectedText(element)
            ?? webArea(containing: element).flatMap(webSelectedText)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Browsers keep the page selection on the web area, which may be an
    /// ancestor of the focused element (a link, for example).
    private static func webArea(containing element: AXUIElement) -> AXUIElement? {
        var current = copyElement(element, kAXParentAttribute)
        for _ in 0..<32 {
            guard let node = current else { return nil }
            if copyString(node, kAXRoleAttribute) == "AXWebArea" { return node }
            current = copyElement(node, kAXParentAttribute)
        }
        return nil
    }

    /// Static web content (WebKit and Chromium) reports its selection as a
    /// text marker range rather than through AXSelectedText.
    private static func webSelectedText(_ element: AXUIElement) -> String? {
        guard let range = copyValue(element, "AXSelectedTextMarkerRange") else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString,
                                                         range, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: - Selection bounds

    /// Reads the bounds of the frontmost app's selection so the result panel can avoid covering it.
    private static func focusedSelectionBounds() -> NSRect? {
        guard let (_, app) = frontmostAppElement(),
              let element = copyElement(app, kAXFocusedUIElementAttribute),
              let primary = NSScreen.screens.first else { return nil }

        let bounds = textBounds(element)
            ?? webBounds(element)
            ?? webArea(containing: element).flatMap(webBounds)
        guard let bounds else { return nil }
        // Accessibility uses a top-left origin on the primary screen; AppKit uses bottom-left.
        return NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY,
                      width: bounds.width, height: bounds.height)
    }

    private static func textBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = copyValue(element, kAXSelectedTextRangeAttribute) else { return nil }
        return copyRect(element, kAXBoundsForRangeParameterizedAttribute, range)
    }

    private static func webBounds(_ element: AXUIElement) -> CGRect? {
        guard let range = copyValue(element, "AXSelectedTextMarkerRange") else { return nil }
        return copyRect(element, "AXBoundsForTextMarkerRange", range)
    }

    /// Returns a non-empty rectangle; collapsed selections report zero-sized bounds.
    private static func copyRect(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // Safe: the type ID was checked above.
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    // MARK: - Attribute helpers

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Safe: the type ID was checked above.
        return (value as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
