#!/usr/bin/env swift
//
// Draws the app icon and writes the asset catalog entry for it.
//
//   swift Scripts/app-icon.swift [output .appiconset directory]
//
// Defaults to Assets.xcassets/AppIcon.appiconset. The result is committed —
// this is here so the icon can be changed by editing a number rather than by
// opening a drawing program.
//
// The seven strokes are the same ones Sources/DejimaMark.swift ships for the
// menu bar; keep them in step. Everything else — the tile, the ink, the light
// the glyph is cut out of — is only ever an icon and lives here.

import AppKit

// MARK: - The mark

/// The strokes in the 120×120 design box, y measured downwards.
let strokes: [CGRect] = [
    CGRect(x: 54, y: 13, width: 12, height: 94),
    CGRect(x: 30, y: 21, width: 12, height: 38),
    CGRect(x: 78, y: 21, width: 12, height: 38),
    CGRect(x: 30, y: 47, width: 60, height: 12),
    CGRect(x: 12, y: 69, width: 12, height: 38),
    CGRect(x: 96, y: 69, width: 12, height: 38),
    CGRect(x: 12, y: 95, width: 96, height: 12),
]
let inkBounds = CGRect(x: 12, y: 13, width: 96, height: 94)

func markPath(fittedInto rect: CGRect) -> NSBezierPath {
    let scale = min(rect.width / inkBounds.width, rect.height / inkBounds.height)
    let size = CGSize(width: inkBounds.width * scale, height: inkBounds.height * scale)
    let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)

    let path = NSBezierPath()
    for stroke in strokes {
        path.appendRect(CGRect(
            x: origin.x + (stroke.minX - inkBounds.minX) * scale,
            y: origin.y + (inkBounds.maxY - stroke.maxY) * scale,
            width: stroke.width * scale,
            height: stroke.height * scale
        ))
    }
    return path
}

// MARK: - The icon

/// Vermilion, for the seal it looks like at a glance.
let ink = NSColor(srgbRed: 0.663, green: 0.231, blue: 0.165, alpha: 1)      // #A93B2A
let inkShade = NSColor(srgbRed: 0.525, green: 0.180, blue: 0.125, alpha: 1) // a touch deeper
let paper = NSColor(srgbRed: 0.984, green: 0.965, blue: 0.937, alpha: 1)    // #FBF6EF

/// Apple's macOS grid: on a 1024 canvas the rounded square is 824 across,
/// leaving room for the shadow every other icon on the Dock casts.
func renderIcon(pixels: Int) -> Data {
    let canvas = CGFloat(pixels)
    let unit = canvas / 1024

    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate a \(pixels)px bitmap") }
    representation.size = CGSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    let tile = CGRect(x: 100 * unit, y: 110 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)

    // The shadow is what makes an icon sit on the Dock rather than float
    // above it. Small, and only underneath.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = CGSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 24 * unit
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSShadow().set()

    // A gradient down the tile, shallow enough to read as one colour.
    NSGradient(colors: [inkShade, ink])!.draw(in: shape, angle: 90)

    paper.setFill()
    markPath(fittedInto: tile.insetBy(dx: tile.width * 0.23, dy: tile.height * 0.23)).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(pixels)px icon as PNG")
    }
    return png
}

// MARK: - Asset catalog

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1]
                    : "Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try renderIcon(pixels: pixels)
        .write(to: directory.appendingPathComponent("icon_\(pixels).png"))
}

// Each size is wanted twice, once as @1x and once as the @2x of the size
// below, and the same file answers for both.
let entries = [(16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128),
               (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024)]
    .map { (points, scale, pixels) in
        """
            {
              "filename" : "icon_\(pixels).png",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """
    }
    .joined(separator: ",\n")

try """
{
  "images" : [
\(entries)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
