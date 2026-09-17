import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        // No-op unless the person opted in, and at most once a day.
        Updater.checkInBackgroundIfDue()
    }
}

/// Owns every moving part and connects them:
/// DoubleCopyMonitor -> LanguageRouter -> TranslationHub -> ResultPanel
@MainActor
final class Controller: ObservableObject {
    let hub = TranslationHub()
    let result = ResultModel()

    @Published private(set) var isMonitoring = false
    @Published private(set) var hasAccessibility = false

    private let monitor = DoubleCopyMonitor()
    private var panel: ResultPanel?
    private var currentJob: Task<Void, Never>?
    /// Bumped per request. A superseded translation can still be mid-chunk
    /// inside the hub, and its partial results must not land in the panel.
    private var generation = 0

    func start() {
        // Whatever the hub needs to be ready. The macOS 15 build puts a hidden
        // window on screen here; the macOS 26 build does nothing.
        hub.start()
        panel = ResultPanel(model: result)

        monitor.onDoubleCopy = { [weak self] text in
            self?.handle(text)
        }
        refreshPermission()
        if hasAccessibility { enableMonitoring() }
    }

    // MARK: - Permission

    func refreshPermission() {
        hasAccessibility = AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time; afterwards it silently returns
    /// the current state, so also open the settings pane for the user.
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let granted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        hasAccessibility = granted
        if granted {
            enableMonitoring()
        } else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Monitoring

    func enableMonitoring() {
        guard !isMonitoring else { return }
        monitor.start()
        isMonitoring = true
    }

    func disableMonitoring() {
        guard isMonitoring else { return }
        monitor.stop()
        isMonitoring = false
    }

    func toggleMonitoring() {
        isMonitoring ? disableMonitoring() : enableMonitoring()
    }

    // MARK: - Translation flow

    /// Re-runs the last translation, e.g. after the user flips the language pair.
    func retranslate() {
        guard !result.sourceText.isEmpty else { return }
        handle(result.sourceText)
    }

    private func handle(_ text: String) {
        // Copied from a PDF, the text arrives broken at the margin. Repair it
        // before anything else looks at it: language detection, the translator
        // and the original shown in the panel all want the real paragraphs.
        let trimmed = TextCleaner.unwrap(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentJob?.cancel()
        generation += 1
        let job = generation

        let route = LanguageRouter.route(for: trimmed)
        result.begin(source: trimmed, route: route)
        panel?.show(near: NSEvent.mouseLocation)

        guard let route else {
            result.fail(DejimaError.noRoute)
            return
        }

        currentJob = Task { [weak self, hub, result] in
            do {
                var output = try await hub.translate(trimmed,
                                                     from: route.source,
                                                     to: route.target) { partial in
                    guard self?.generation == job else { return }
                    result.stream(partial)
                }
                if Polisher.isEnabled {
                    result.beginRefining()
                    output = await Polisher.polish(original: trimmed,
                                                   draft: output,
                                                   target: route.target)
                }
                guard !Task.isCancelled else { return }
                result.succeed(output)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                result.fail(error)
            }
        }
    }

    func copyResult() {
        guard let text = result.copyableText else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func hidePanel() {
        panel?.hide()
    }
}

enum DejimaError: LocalizedError {
    case noRoute

    var errorDescription: String? {
        switch self {
        case .noRoute:
            return "Dejima couldn't tell what language this is. Pick a source language in the menu and copy again."
        }
    }
}
