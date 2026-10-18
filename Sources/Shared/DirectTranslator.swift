import Foundation
import NaturalLanguage
import Translation

/// Creates translation sessions directly on macOS 26 and later.
/// Requires an identified source language and installed language models;
/// this API cannot prompt for model downloads.
@available(macOS 26, *)
@MainActor
final class DirectTranslator: Translator {
    /// Direct sessions need no host window.
    func start() {}

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
        for chunk in TranslationHub.chunk(text) {
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
            return String(localized: "The languages for \(pair) aren't downloaded yet. Open “Translation language settings” in the menu to download them, then try again.")
        }
    }
}
