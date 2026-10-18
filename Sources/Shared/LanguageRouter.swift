import Foundation
import NaturalLanguage

struct Route {
    var source: Locale.Language?
    var target: Locale.Language
}

/// Translate into the primary language, or into the secondary language
/// when the source already matches the primary language.
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
            // Defer source detection to the translation hub.
            return Route(source: nil, target: primaryLanguage)
        }

        if detected.isEquivalent(to: primaryLanguage) {
            return Route(source: detected, target: secondaryLanguage)
        }
        return Route(source: detected, target: primaryLanguage)
    }

    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let hypothesis = recognizer.dominantLanguage else { return nil }
        // Reject uncertain language guesses for short selections.
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[hypothesis] ?? 0
        guard confidence > 0.4 || text.count > 12 else { return nil }
        return Locale.Language(identifier: hypothesis.rawValue)
    }

    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Omit regions and default scripts from display names. Keep non-default
    /// scripts to distinguish variants such as Traditional and Simplified Chinese.
    static func displayName(_ language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else {
            return language.minimalIdentifier
        }
        var identifier = code
        let defaultScript = Locale.Language(identifier: code).script?.identifier
        if let script = language.script?.identifier, script != defaultScript {
            identifier += "-\(script)"
        }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    static let choices = ["zh-Hans", "zh-Hant", "ja", "en", "ko", "de", "fr", "es", "ru"]
}

private extension Locale.Language {
    /// `zh-Hans` and `zh` should count as the same language for routing.
    func isEquivalent(to other: Locale.Language) -> Bool {
        languageCode == other.languageCode
    }
}
