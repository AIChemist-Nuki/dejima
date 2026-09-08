import Foundation
import NaturalLanguage

struct Route {
    var source: Locale.Language?
    var target: Locale.Language
}

/// Decides which way to translate.
///
/// Default behaviour: everything becomes your primary language, except your
/// primary language itself, which becomes the secondary one. Reading Japanese
/// papers all day and occasionally drafting a reply in Japanese both work
/// without touching a setting.
enum LanguageRouter {
    static var primary: String {
        get { UserDefaults.standard.string(forKey: "primaryLanguage") ?? "zh-Hans" }
        set { UserDefaults.standard.set(newValue, forKey: "primaryLanguage") }
    }

    static var secondary: String {
        get { UserDefaults.standard.string(forKey: "secondaryLanguage") ?? "ja" }
        set { UserDefaults.standard.set(newValue, forKey: "secondaryLanguage") }
    }

    static func route(for text: String) -> Route? {
        let detected = detect(text)
        let primaryLanguage = Locale.Language(identifier: primary)
        let secondaryLanguage = Locale.Language(identifier: secondary)

        guard let detected else {
            // Unknown script: let the framework guess the source, aim at primary.
            return Route(source: nil, target: primaryLanguage)
        }

        // Translating a language into itself is always rejected by the framework.
        if detected.isEquivalent(to: primaryLanguage) {
            return Route(source: detected, target: secondaryLanguage)
        }
        return Route(source: detected, target: primaryLanguage)
    }

    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let hypothesis = recognizer.dominantLanguage else { return nil }
        // Short strings get low-confidence guesses; don't trust those.
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[hypothesis] ?? 0
        guard confidence > 0.4 || text.count > 12 else { return nil }
        return Locale.Language(identifier: hypothesis.rawValue)
    }

    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Languages worth offering in the menu. Apple supports more; trim or extend
    /// to taste.
    static let choices = ["zh-Hans", "zh-Hant", "ja", "en", "ko", "de", "fr", "es", "ru"]
}

private extension Locale.Language {
    /// `zh-Hans` and `zh` should count as the same language for routing.
    func isEquivalent(to other: Locale.Language) -> Bool {
        languageCode == other.languageCode
    }
}
