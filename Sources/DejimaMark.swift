import AppKit

/// The 出 monogram, drawn from seven rectangles.
///
/// 出 is "out" — the character on the gate of the island the app is named
/// after, and the shape of what the app does to a sentence. Built from bare
/// rectangles rather than set in a typeface so it stays legible at 16 points
/// in a menu bar, where a real glyph's strokes would close up.
///
/// Scripts/app-icon.swift draws the same seven strokes for the app icon.
/// They have to agree; this is the copy that ships.
enum DejimaMark {
    /// The strokes in the 120×120 design box, y measured downwards: a spine,
    /// two pairs of brackets, and the bars that close them.
    static let strokes: [CGRect] = [
        CGRect(x: 54, y: 13, width: 12, height: 94),
        CGRect(x: 30, y: 21, width: 12, height: 38),
        CGRect(x: 78, y: 21, width: 12, height: 38),
        CGRect(x: 30, y: 47, width: 60, height: 12),
        CGRect(x: 12, y: 69, width: 12, height: 38),
        CGRect(x: 96, y: 69, width: 12, height: 38),
        CGRect(x: 12, y: 95, width: 96, height: 12),
    ]

    /// What the strokes actually cover. Fitting to this rather than to the
    /// design box keeps the mark from floating inside its own margins.
    static let inkBounds = CGRect(x: 12, y: 13, width: 96, height: 94)

    /// The mark, centred in `rect` at the largest size that fits, in a
    /// coordinate space whose y grows upwards.
    static func path(fittedInto rect: CGRect) -> NSBezierPath {
        let scale = min(rect.width / inkBounds.width, rect.height / inkBounds.height)
        let size = CGSize(width: inkBounds.width * scale, height: inkBounds.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)

        let path = NSBezierPath()
        for stroke in strokes {
            path.appendRect(CGRect(
                x: origin.x + (stroke.minX - inkBounds.minX) * scale,
                // The design box measures y downwards; this one measures up.
                y: origin.y + (inkBounds.maxY - stroke.maxY) * scale,
                width: stroke.width * scale,
                height: stroke.height * scale
            ))
        }
        return path
    }

    /// The menu bar icon. A template image, so the bar inverts it when the
    /// menu opens and follows light and dark without being told.
    static func menuBarImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            path(fittedInto: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dejima"
        return image
    }
}
