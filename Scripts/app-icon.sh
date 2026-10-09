#!/bin/bash
set -euo pipefail

# Export packaging icons from the Icon Composer document.
cd "$(dirname "$0")/.."
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [ -d "$developer_dir/Contents/Developer" ]; then
    developer_dir="$developer_dir/Contents/Developer"
fi
export DEVELOPER_DIR="$developer_dir"
ictool="$developer_dir/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [ ! -x "$ictool" ]; then
    echo "error: select Xcode 27 or later with xcode-select or DEVELOPER_DIR" >&2
    exit 1
fi

rendered="build/icon-export/rendered"
catalog="Assets.xcassets/AppIcon.appiconset"
mkdir -p "$rendered"

for pixels in 16 32 64 128 256 512 1024; do
    "$ictool" AppIcon.icon --export-image \
        --output-file "$rendered/icon_$pixels.png" \
        --platform macOS --rendition Default \
        --width "$pixels" --height "$pixels" --scale 1 --design-generation 27
done

# Flattened exports fill the canvas; traditional macOS icons need outer margins.
xcrun swift -module-cache-path build/icon-export/module-cache - "$rendered" "$catalog" <<'SWIFT'
import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let filename = "icon_\(pixels).png"
    guard let image = NSImage(contentsOf: source.appendingPathComponent(filename)),
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
          ) else {
        fatalError("Could not load or allocate \(filename)")
    }

    let canvas = CGFloat(pixels)
    let inset = canvas * 100 / 1024
    bitmap.size = CGSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(filename)")
    }
    try png.write(to: destination.appendingPathComponent(filename))
}
SWIFT
