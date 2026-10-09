import AppKit

/// Observes double-copy gestures without consuming the copy keystrokes.
/// Global key monitoring requires Accessibility access.
@MainActor
final class DoubleCopyMonitor {
    var onDoubleCopy: ((String) -> Void)?

    /// Maximum interval between copy presses.
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return }

        let now = event.timestamp
        defer { lastCopyAt = now }
        guard now - lastCopyAt < window else { return }

        lastCopyAt = -.greatestFiniteMagnitude
        readPasteboard()
    }

    /// The source app may not have handled the copy event yet. Wait for a
    /// pasteboard change, with a timeout if its contents are unchanged.
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
