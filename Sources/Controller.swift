import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
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
    private var host: TranslationHostWindow?
    private var panel: ResultPanel?
    private var currentJob: Task<Void, Never>?

    func start() {
        // The translationTask host must live in a window that is actually on
        // screen, otherwise SwiftUI never runs the task and no session arrives.
        host = TranslationHostWindow(hub: hub)
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentJob?.cancel()

        let route = LanguageRouter.route(for: trimmed)
        result.begin(source: trimmed, route: route)
        panel?.show(near: NSEvent.mouseLocation)

        guard let route else {
            result.fail(DejimaError.noRoute)
            return
        }

        currentJob = Task { [hub, result] in
            do {
                var output = try await hub.translate(trimmed,
                                                     from: route.source,
                                                     to: route.target)
                if Polisher.isEnabled {
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
        guard case .done(let text) = result.state else { return }
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
