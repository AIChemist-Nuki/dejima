import Foundation
import NaturalLanguage
import Translation

/// Creates translation sessions directly on macOS 26 and later.
/// Requires an identified source language and installed language models;
/// this API cannot prompt for model downloads.
@MainActor
final class TranslationHub {
    /// Retained for the shared interface; direct sessions need no host window.
    func start() {}

    /// - Parameter onPartial: Receives the accumulated translation after each chunk.
    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let from = source ?? Self.bestGuess(for: text) else {
            throw TranslationHubError.unknownSourceLanguage
        }

        // Report missing models with installation instructions.
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

    /// Direct sessions require a source language, so retry detection without
    /// LanguageRouter's confidence threshold.
    private static func bestGuess(for text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
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
