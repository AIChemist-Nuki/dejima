import SwiftUI
import Translation

/// Turns Apple's view-bound translation API into a plain `async` function.
///
/// `TranslationSession` can only be handed to you inside SwiftUI's
/// `.translationTask` modifier — there is no "give me a session" call. So a
/// 1×1 invisible window hosts a view carrying that modifier, and this object
/// shuttles requests to it: set a configuration, the closure fires, the closure
/// resumes the waiting continuation.
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

    /// Puts the host window on screen. It has to be up before the first
    /// translation, or there is no view for `.translationTask` to run on.
    func start() {
        host = TranslationHostWindow(hub: self)
    }

    /// - Parameter onPartial: Called with everything translated so far each
    ///   time a chunk lands, so long text can appear a paragraph at a time.
    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        pending?.continuation.resume(throwing: CancellationError())
        pending = nil

        return try await withCheckedThrowingContinuation { continuation in
            pending = Job(text: text, onPartial: onPartial, continuation: continuation)

            if configuration?.source == source, configuration?.target == target {
                // Same pair as last time: the configuration compares equal and
                // SwiftUI would skip the task. invalidate() forces a re-run.
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

    /// One request per paragraph — after `TextCleaner`, each line is one.
    /// Translation time grows with length (about 2 s for a 450-character
    /// paragraph), so the first paragraph appears after its own time instead of
    /// after a whole batch. Batching saves nothing: the total and the output
    /// come out the same, because the model translates each paragraph on its
    /// own even when they share a request.
    static func chunk(_ text: String, limit: Int = 1200) -> [String] {
        var chunks: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var rest = Substring(paragraph.trimmingCharacters(in: .whitespaces))
            // The framework rejects very long strings, so a paragraph past the
            // limit still has to be cut.
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

/// A 1×1, fully transparent window pinned to the corner of the main screen.
/// It has to be genuinely on screen — an off-screen or ordered-out window means
/// SwiftUI treats the view as never appearing and the task never runs.
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
