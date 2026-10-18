import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional on-device revision using the source text and translation draft.
enum Polisher {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: "polishWithAppleIntelligence")
    }

    static func polish(original: String, draft: String, target: Locale.Language) async -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isEnabled else { return draft }

        let language = Locale.current.localizedString(
            forIdentifier: target.maximalIdentifier
        ) ?? target.maximalIdentifier

        let instructions = """
        You revise machine translations. Return only the corrected translation \
        in \(language) — no notes, no alternatives, no quotation marks. Keep the \
        original's register and paragraph breaks. Leave proper nouns, gene and \
        protein names, chemical names, units, and citations exactly as written \
        in the source.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: """
            Source:
            \(original)

            Draft translation:
            \(draft)
            """)
            let revised = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return revised.isEmpty ? draft : revised
        } catch {
            // Keep the draft if revision fails or the model refuses the request.
            return draft
        }
        #else
        return draft
        #endif
    }
}
