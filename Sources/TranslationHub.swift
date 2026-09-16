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

    /// The framework rejects very long strings. Split on paragraphs and refill
    /// up to a safe size so a whole abstract still goes through in one go.
    static func chunk(_ text: String, limit: Int = 1200) -> [String] {
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > limit, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? paragraph : "\n" + paragraph
            // A single paragraph longer than the limit still has to be cut.
            while current.count > limit {
                let cut = current.index(current.startIndex, offsetBy: limit)
                chunks.append(String(current[..<cut]))
                current = String(current[cut...])
            }
        }
        if !current.isEmpty { chunks.append(current) }
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
final class TranslationHostWindow {
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
