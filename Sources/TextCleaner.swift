import Foundation

/// Repairs text copied out of a PDF.
///
/// A PDF has no idea what a paragraph is. Every visual line is its own line, so
/// copying one paragraph gives you text chopped at the right margin, with words
/// split across a hyphen. Handing that to a translator produces mush, because
/// each fragment gets treated as a sentence of its own.
///
/// The load-bearing assumption is that a hard-wrapped line reaches the margin.
/// Only lines close to the longest one in the selection are candidates for
/// joining, which leaves headings, list items, addresses and code alone without
/// needing to recognise what any of them are.
enum TextCleaner {
    /// Fraction of the longest line a line must reach to count as wrapped.
    private static let wrapRatio = 0.66

    static func unwrap(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "")  // soft hyphen

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count > 1, let longest = lines.map(\.count).max(), longest > 0 else {
            return normalized
        }
        let threshold = Int(Double(longest) * wrapRatio)

        var output = ""
        var lastLine = ""
        var blankLineSeen = false

        for line in lines {
            if line.isEmpty {
                blankLineSeen = !output.isEmpty
                lastLine = ""
                continue
            }
            if output.isEmpty {
                output = line
            } else if blankLineSeen {
                // A blank line is the one paragraph break a PDF gives you
                // outright; keep it.
                output += "\n\n" + line
            } else if let joined = join(output, lastLine: lastLine, with: line, threshold: threshold) {
                output = joined
            } else {
                output += "\n" + line
            }
            blankLineSeen = false
            lastLine = line
        }

        return output
    }

    /// The paragraph so far plus `next`, or nil to keep the line break.
    ///
    /// `lastLine` is the most recent *visual* line rather than the accumulated
    /// paragraph — the length test only makes sense against one line.
    private static func join(_ paragraph: String,
                             lastLine: String,
                             with next: String,
                             threshold: Int) -> String? {
        // A split word is one word however short its line was.
        if let stem = dehyphenated(paragraph), startsLowercaseLetter(next) {
            return stem + next
        }
        let required = max(threshold, minWrapLength(for: lastLine))
        guard lastLine.count >= required, !startsNewBlock(next) else { return nil }
        return paragraph + separator(between: paragraph, and: next) + next
    }

    /// How long a line has to be, in absolute terms, before it can plausibly
    /// have been wrapped at a margin.
    ///
    /// The ratio alone is not enough: two short lines of equal length pass it
    /// trivially, which would fuse a two-line selection that was deliberately
    /// broken. CJK carries far more per character, so its lines are legitimately
    /// shorter than a Latin one — a Japanese PDF column runs about 15 characters
    /// where an English one runs 70.
    private static func minWrapLength(for line: String) -> Int {
        let cjk = line.filter(isCJK).count
        return Double(cjk) / Double(line.count) > 0.3 ? 12 : 25
    }

    /// Drops a trailing hyphen that exists only because the word hit the
    /// margin. Requires a letter in front of it, so a range like "1990-" or a
    /// dash used as punctuation is left alone.
    private static func dehyphenated(_ paragraph: String) -> String? {
        let hyphens: Set<Character> = ["-", "\u{2010}", "\u{2011}"]
        guard let last = paragraph.last, hyphens.contains(last) else { return nil }
        let stem = paragraph.dropLast()
        guard let letter = stem.last, letter.isLetter else { return nil }
        return String(stem)
    }

    private static func startsLowercaseLetter(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first.isLetter && first.isLowercase
    }

    /// Lines that begin something new, where the break carries meaning.
    private static func startsNewBlock(_ line: String) -> Bool {
        // A lone number is a page number that got caught in the selection.
        if line.allSatisfy(\.isNumber) { return true }
        return startsListItem(line)
    }

    private static func startsListItem(_ line: String) -> Bool {
        let bullets: Set<Character> = ["•", "·", "‣", "▪", "◦", "*", "-", "–", "—"]
        let characters = Array(line)
        guard let first = characters.first else { return false }

        if bullets.contains(first) {
            // Bullets are followed by a space; "-30 °C" is not a list.
            return characters.count > 1 && characters[1] == " "
        }

        // "1. ", "2) " or "(3) "
        var index = first == "(" ? 1 : 0
        var digits = 0
        while index < characters.count, characters[index].isNumber, digits < 3 {
            index += 1
            digits += 1
        }
        guard digits > 0, index < characters.count else { return false }
        guard characters[index] == "." || characters[index] == ")" else { return false }
        index += 1
        return index == characters.count || characters[index] == " "
    }

    /// CJK writing puts no spaces between words; everything else does.
    private static func separator(between left: String, and right: String) -> String {
        guard let last = left.last else { return "" }
        // A hyphen that survived `dehyphenated` is part of a range or a
        // compound: "20-" + "30 °C" should not gain a space.
        if last == "-" || isCJK(last) { return "" }
        if let first = right.first, isCJK(first) { return "" }
        return " "
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,    // CJK punctuation
             0x3040...0x30FF,    // hiragana, katakana
             0x3400...0x4DBF,    // unified ideographs extension A
             0x4E00...0x9FFF,    // unified ideographs
             0xF900...0xFAFF,    // compatibility ideographs
             0xFF00...0xFF60,    // fullwidth forms
             0x20000...0x2FA1F:  // extensions B and later
            return true
        default:
            // Hangul is deliberately absent: Korean does use spaces.
            return false
        }
    }
}
