import SwiftUI
import Translation

/// Adapts the view-bound translation API to async calls on macOS 15.
/// A hidden SwiftUI host provides sessions through translationTask,
/// which resumes the pending continuation.
@MainActor
final class TranslationHub: ObservableObject {
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
        host = TranslationHostWindow(hub: self)
    }

    /// - Parameter onPartial: Receives the accumulated translation after each chunk.
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
            for chunk in Self.chunk(job.text) {
                let response = try await session.translate(chunk)
                parts.append(response.targetText)
                job.onPartial(parts.joined(separator: "\n\n"))
            }
            job.continuation.resume(returning: parts.joined(separator: "\n\n"))
        } catch {
            job.continuation.resume(throwing: error)
        }
    }

    /// Translate paragraphs separately so results can appear incrementally.
    /// Split paragraphs longer than the request limit.
    static func chunk(_ text: String, limit: Int = 1200) -> [String] {
        var chunks: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var rest = Substring(paragraph.trimmingCharacters(in: .whitespaces))
            while rest.count > limit {
                let cut = rest.index(rest.startIndex, offsetBy: limit)
                chunks.append(String(rest[..<cut]))
                rest = rest[cut...]
            }
            if !rest.isEmpty { chunks.append(String(rest)) }
        }
        return chunks
    }
}

// MARK: - Invisible host

private struct TranslationHostView: View {
    @ObservedObject var hub: TranslationHub

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(hub.configuration) { session in
                await hub.serve(session)
            }
    }
}

/// The transparent host must remain on-screen and ordered in. Otherwise
/// SwiftUI does not activate the view's translationTask.
@MainActor
private final class TranslationHostWindow {
    private let window: NSWindow

    init(hub: TranslationHub) {
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        window = NSWindow(contentRect: NSRect(origin: origin, size: CGSize(width: 1, height: 1)),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.contentView = NSHostingView(rootView: TranslationHostView(hub: hub))
        window.alphaValue = 0
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
    }
}
