import SwiftUI
import Translation

/// Adapts the view-bound translation API to async calls on macOS 15–25.
/// A hidden SwiftUI host provides sessions through translationTask,
/// which resumes the pending continuation.
@MainActor
final class HostedTranslator: ObservableObject, Translator {
    @Published fileprivate var configuration: TranslationSession.Configuration?

    private struct Job {
        let text: String
        let onPartial: @MainActor (String) -> Void
        let continuation: CheckedContinuation<String, Error>
    }
    private var pending: Job?
    private var host: TranslationHostWindow?

    /// Create the host before translating so translationTask has an active view.
    func start() {
        host = TranslationHostWindow(translator: self)
    }

    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        pending?.continuation.resume(throwing: CancellationError())
        pending = nil

        return try await withCheckedThrowingContinuation { continuation in
            pending = Job(text: text, onPartial: onPartial, continuation: continuation)

            if configuration?.source == source, configuration?.target == target {
                // Invalidate an unchanged language pair to make SwiftUI rerun the task.
                configuration?.invalidate()
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
        }
    }

    fileprivate func serve(_ session: TranslationSession) async {
        guard let job = pending else { return }
        pending = nil

        do {
            var parts: [String] = []
            for chunk in TranslationHub.chunk(job.text) {
                let response = try await session.translate(chunk)
                parts.append(response.targetText)
                job.onPartial(parts.joined(separator: "\n\n"))
            }
            job.continuation.resume(returning: parts.joined(separator: "\n\n"))
        } catch {
            job.continuation.resume(throwing: error)
        }
    }
}

// MARK: - Invisible host

private struct TranslationHostView: View {
    @ObservedObject var translator: HostedTranslator

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(translator.configuration) { session in
                await translator.serve(session)
            }
    }
}

/// The transparent host must remain on-screen and ordered in. Otherwise
/// SwiftUI does not activate the view's translationTask.
@MainActor
private final class TranslationHostWindow {
    private let window: NSWindow

    init(translator: HostedTranslator) {
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        window = NSWindow(contentRect: NSRect(origin: origin, size: CGSize(width: 1, height: 1)),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.contentView = NSHostingView(rootView: TranslationHostView(translator: translator))
        window.alphaValue = 0
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
    }
}
