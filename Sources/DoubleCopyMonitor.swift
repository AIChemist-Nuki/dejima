import AppKit

/// Watches for two ⌘C presses in quick succession, then reads the pasteboard.
///
/// This *observes* key events instead of registering ⌘C as a global hotkey.
/// `RegisterEventHotKey` would swallow the keystroke and break normal copying;
/// an NSEvent monitor cannot consume events at all, which is exactly what we
/// want here. The price is the Accessibility permission.
@MainActor
final class DoubleCopyMonitor {
    var onDoubleCopy: ((String) -> Void)?

    /// How long the second ⌘C may arrive after the first.
    var window: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "doublePressWindow")
        return stored > 0 ? stored : 0.45
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastCopyAt: TimeInterval = -.greatestFiniteMagnitude

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
        guard event.keyCode == keyCodeC else { return }
        // Exactly ⌘C — not ⌘⇧C, ⌘⌥C, ⌃⌘C.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return }

        let now = event.timestamp
        defer { lastCopyAt = now }
        guard now - lastCopyAt < window else { return }

        lastCopyAt = -.greatestFiniteMagnitude  // consume, so ⌘C×3 isn't two hits
        readPasteboard()
    }

    /// The keystroke we just saw hasn't reached the frontmost app yet, so the
    /// pasteboard still holds the old value. Poll `changeCount` until the app
    /// writes, with a short ceiling for apps that had nothing selected.
    private func readPasteboard(attemptsLeft: Int = 15) {
        let pasteboard = NSPasteboard.general
        let baseline = pasteboard.changeCount

        func poll(_ remaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self else { return }
                if pasteboard.changeCount != baseline || remaining == 0 {
                    if let text = pasteboard.string(forType: .string) {
                        self.onDoubleCopy?(text)
                    }
                } else {
                    poll(remaining - 1)
                }
            }
        }
        poll(attemptsLeft)
    }
}
