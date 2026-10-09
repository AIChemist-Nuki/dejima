import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        Updater.checkInBackgroundIfDue()
    }
}

/// Coordinates copy monitoring, language routing, translation, and results.
@MainActor
final class Controller: ObservableObject {
    let hub = TranslationHub()
    let result = ResultModel()

    @Published private(set) var isMonitoring = false
    @Published private(set) var hasAccessibility = false

    private let monitor = DoubleCopyMonitor()
    private var panel: ResultPanel?
    private var guide: PermissionGuide?
    private var currentJob: Task<Void, Never>?
    /// Reject partial results from superseded requests, even if cancellation is delayed.
    private var generation = 0

    func start() {
        hub.start()
        panel = ResultPanel(model: result)

        monitor.onDoubleCopy = { [weak self] text in
            self?.handle(text)
        }
        refreshPermission()
        if hasAccessibility {
            enableMonitoring()
        } else {
            showPermissionGuide()
        }
    }

    // MARK: - Permission

    func refreshPermission() {
        hasAccessibility = AXIsProcessTrusted()
    }

    /// Show the guide if access is denied, since the system prompt may not reappear.
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let granted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        hasAccessibility = granted
        if granted {
            enableMonitoring()
        } else {
            showPermissionGuide()
        }
    }

    private func showPermissionGuide() {
        if guide == nil {
            guide = PermissionGuide { [weak self] in
                guard let self else { return }
                self.hasAccessibility = true
                // Reinstall monitors so the permission takes effect without relaunching.
                self.enableMonitoring()
            }
        }
        guide?.show()
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

    func retranslate() {
        guard !result.sourceText.isEmpty else { return }
        handle(result.sourceText)
    }

    private func handle(_ text: String) {
        // Normalize PDF line wraps before detection, translation, and display.
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
            return String(localized: "Dejima couldn't tell what language this is. Pick a source language in the menu and copy again.")
        }
    }
}
