import Foundation
import NaturalLanguage
import Translation

/// The macOS 26 build's translator. Same surface as the legacy one, none of
/// the machinery.
///
/// `TranslationSession(installedSource:target:)` hands out a session directly,
/// so everything the view-bound API forced on the legacy build is gone: no 1×1
/// host window pinned to the corner of the screen, no configuration-equality
/// dance with `invalidate()`, no continuation shuttling between a SwiftUI
/// closure and an `async` function.
///
/// Two capabilities go with it, and both are deliberate trade-offs of this
/// build rather than oversights:
///
/// - **The source language is required.** A directly created session will not
///   identify it for you, so an uncertain guess has to be committed to instead
///   of deferred to the framework.
/// - **The session cannot request downloads.** A missing language pair throws
///   rather than prompting, so the error points at the menu item that installs
///   models. The legacy build gets the system's download sheet instead.
@MainActor
final class TranslationHub {
    /// Nothing to set up. The legacy build uses this to put its host window on
    /// screen; here a session is made on demand.
    func start() {}

    /// - Parameter onPartial: Called with everything translated so far each
    ///   time a chunk lands, so long text can appear a paragraph at a time.
    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let from = source ?? Self.bestGuess(for: text) else {
            throw TranslationHubError.unknownSourceLanguage
        }

        // Checked up front so a missing model reads as an instruction rather
        // than as a framework error code.
        let availability = LanguageAvailability()
        guard await availability.status(from: from, to: target) == .installed else {
            throw TranslationHubError.notInstalled(source: from, target: target)
        }

        let session = TranslationSession(installedSource: from, target: target)
        var parts: [String] = []
        for chunk in Self.chunk(text) {
            try Task.checkCancellation()
            let response = try await session.translate(chunk)
            parts.append(response.targetText)
            onPartial(parts.joined(separator: "\n\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    /// `LanguageRouter` withholds low-confidence guesses so the framework can
    /// decide instead. Here there is no framework to defer to, and the best
    /// available guess beats refusing to translate at all — a wrong guess is
    /// visible in the panel's badge and fixable from the menu.
    private static func bestGuess(for text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
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

enum TranslationHubError: LocalizedError {
    case unknownSourceLanguage
    case notInstalled(source: Locale.Language, target: Locale.Language)

    var errorDescription: String? {
        switch self {
        case .unknownSourceLanguage:
            return String(localized: "Dejima couldn't tell what language this is. Pick a source language in the menu and copy again.")
        case .notInstalled(let source, let target):
            let pair = "\(LanguageRouter.displayName(source)) → \(LanguageRouter.displayName(target))"
            return String(localized: "\(pair) isn't downloaded yet. Use “Check language models…” in the menu to install it, then copy again.")
        }
    }
}
