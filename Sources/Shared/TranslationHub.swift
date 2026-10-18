import Foundation

/// Picks the translation implementation for the running macOS version.
/// macOS 26 and later create sessions directly; earlier versions borrow
/// sessions from a hidden SwiftUI host.
@MainActor
final class TranslationHub {
    private let translator: any Translator

    init() {
        if #available(macOS 26, *) {
            translator = DirectTranslator()
        } else {
            translator = HostedTranslator()
        }
    }

    /// Call once at launch, before the first translation.
    func start() {
        translator.start()
    }

    /// - Parameter onPartial: Receives the accumulated translation after each chunk.
    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        try await translator.translate(text, from: source, to: target, onPartial: onPartial)
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

@MainActor
protocol Translator: AnyObject {
    func start()
    func translate(_ text: String,
                   from source: Locale.Language?,
                   to target: Locale.Language,
                   onPartial: @escaping @MainActor (String) -> Void) async throws -> String
}
