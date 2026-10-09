import AppKit

/// The 出 monogram, drawn from rectangles for legibility at menu-bar sizes.
/// Keep the strokes in sync with Scripts/app-icon.swift.
enum DejimaMark {
    /// Stroke coordinates in a 120×120 design box, with y increasing downward.
    static let strokes: [CGRect] = [
        CGRect(x: 54, y: 13, width: 12, height: 94),
        CGRect(x: 30, y: 21, width: 12, height: 38),
        CGRect(x: 78, y: 21, width: 12, height: 38),
        CGRect(x: 30, y: 47, width: 60, height: 12),
        CGRect(x: 12, y: 69, width: 12, height: 38),
        CGRect(x: 96, y: 69, width: 12, height: 38),
        CGRect(x: 12, y: 95, width: 96, height: 12),
    ]

    /// Fit to the visible strokes, excluding the design-box margins.
    static let inkBounds = CGRect(x: 12, y: 13, width: 96, height: 94)

    /// Fit and center the mark in a coordinate space with y increasing upward.
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

    /// A template image lets AppKit handle menu selection and appearance changes.
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
