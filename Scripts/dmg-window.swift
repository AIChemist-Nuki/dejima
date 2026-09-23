#!/usr/bin/env swift
//
// Draws and installs the guided windows of the release DMG.
//
//   swift Scripts/dmg-window.swift art <output directory> <version>
//   swift Scripts/dmg-window.swift layout <mounted volume> <newer folder> <older folder>
//
// `art` draws the backgrounds as @1x/@2x pairs; release.sh pairs each into one
// HiDPI TIFF. `layout` writes the .DS_Store files that tell Finder how big the
// windows are, where the icons sit, and which background to draw behind them.
//
// Both halves live here because they are two views of one set of coordinates:
// the arrow points at where the Applications alias is, and only this file
// knows both. Everything is measured in window points from the top-left of
// the window's content area — the same frame Finder positions icons in, and
// the same one the background image is drawn into, one point to one point.
//
// Why not AppleScript, as every DMG recipe on the internet does? Finder on
// macOS 26 and later accepts `set icon size`, `set arrangement` and `set
// background picture` and then quietly writes its own defaults to .DS_Store
// instead. Window bounds and icon positions still survive, so the usual
// recipe half-works, which is worse than not working. Writing the file
// ourselves is the part that can't be argued with.

import AppKit
import Carbon

// MARK: - Geometry

/// The window you land in: two builds, pick one.
enum Root {
    static let size = CGSize(width: 660, height: 520)
    static let iconSize: CGFloat = 80
    /// Icon centres. The captions drawn under each slot have to agree.
    static let newer = CGPoint(x: 200, y: 292)
    static let older = CGPoint(x: 460, y: 292)
    static let readMe = CGPoint(x: 584, y: 452)
    static let slotWidth: CGFloat = 240
}

/// Inside either build: drag it across.
enum Build {
    static let size = CGSize(width: 540, height: 360)
    static let iconSize: CGFloat = 96
    static let app = CGPoint(x: 140, y: 200)
    static let applications = CGPoint(x: 400, y: 200)
}

// MARK: - Palette

/// The monogram's own palette — warm paper, near-black ink, and the vermilion
/// of the mark for the one thing on screen that is an instruction.
enum Palette {
    static let top = NSColor(srgbRed: 0.996, green: 0.990, blue: 0.976, alpha: 1)     // #FEFCF9
    static let bottom = NSColor(srgbRed: 0.937, green: 0.918, blue: 0.886, alpha: 1)  // #EFEAE2
    static let ink = NSColor(srgbRed: 0.086, green: 0.075, blue: 0.059, alpha: 1)     // #16130F
    static let muted = NSColor(srgbRed: 0.267, green: 0.243, blue: 0.212, alpha: 1)
    static let faint = NSColor(srgbRed: 0.420, green: 0.388, blue: 0.353, alpha: 1)   // #6B635A
    static let rule = NSColor(srgbRed: 0.616, green: 0.573, blue: 0.494, alpha: 0.45) // #E3DDD2, ish
    static let card = NSColor(srgbRed: 1, green: 0.992, blue: 0.973, alpha: 0.72)     // #FFFDF8
    static let accent = NSColor(srgbRed: 0.663, green: 0.231, blue: 0.165, alpha: 1)  // #A93B2A
}

// MARK: - Type

/// CJK glyphs differ between Chinese and Japanese, and the system font picks
/// its fallback from the *renderer's* locale rather than from the text.
/// Naming the family keeps the output the same whoever runs the release.
enum Script {
    case latin, chinese, japanese
    /// The wordmark, set in a mincho serif the way the logo sheet has it.
    case wordmark

    var family: String? {
        switch self {
        case .latin: return nil
        case .chinese: return "PingFang SC"
        case .japanese: return "Hiragino Sans"
        case .wordmark: return "Hiragino Mincho ProN"
        }
    }
}

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, _ script: Script = .latin) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight)
    guard let family = script.family else { return system }
    // Built from a bare descriptor, not from the system font's: the system
    // font's descriptor is a placeholder that quietly ignores a new family
    // and hands the system font straight back.
    let descriptor = NSFontDescriptor(fontAttributes: [
        .family: family,
        .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
    ])
    return NSFont(descriptor: descriptor, size: size) ?? system
}

/// Draws one line, positioned by its distance from the top of the canvas, so
/// the drawing code and the icon positions can be read against each other.
func line(_ string: String,
          font: NSFont,
          color: NSColor,
          alignment: NSTextAlignment = .center,
          top: CGFloat,
          left: CGFloat = 0,
          width: CGFloat,
          canvas: CGSize) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byClipping
    let attributed = NSAttributedString(string: string, attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ])
    // The context is not flipped, so text fills a rect from its top edge down.
    let height = ceil(font.ascender - font.descender) + 2
    attributed.draw(in: CGRect(x: left, y: canvas.height - top - height, width: width, height: height))
}

/// A rounded frame, positioned from the top like `line`.
func frame(top: CGFloat,
           left: CGFloat,
           width: CGFloat,
           height: CGFloat,
           canvas: CGSize,
           fill: NSColor?,
           stroke: NSColor,
           dashed: Bool = false) {
    let rect = CGRect(x: left, y: canvas.height - top - height, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
    if let fill {
        fill.setFill()
        path.fill()
    }
    path.lineWidth = dashed ? 2 : 1
    if dashed { path.setLineDash([7, 5], count: 2, phase: 0) }
    stroke.setStroke()
    path.stroke()
}

// MARK: - Canvas

func render(_ size: CGSize, scale: CGFloat, _ body: (CGSize) -> Void) -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fail("could not allocate a \(size) bitmap") }
    // Declaring the size in points is what makes the context scale for us, so
    // the drawing code never has to know about @2x.
    representation.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGradient(colors: [Palette.bottom, Palette.top])!
        .draw(in: CGRect(origin: .zero, size: size), angle: 90)
    body(size)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fail("could not encode the bitmap as PNG")
    }
    return png
}

func drawArt(into directory: URL, version: String, icon: NSImage) throws {
    func write(_ name: String, _ size: CGSize, _ body: @escaping (CGSize) -> Void) throws {
        for (suffix, scale) in [("", CGFloat(1)), ("@2x", CGFloat(2))] {
            try render(size, scale: scale, body)
                .write(to: directory.appendingPathComponent("\(name)\(suffix).png"))
        }
    }

    try write("root", Root.size) { canvas in
        let mark: CGFloat = 60
        icon.draw(in: CGRect(x: (canvas.width - mark) / 2, y: canvas.height - 28 - mark,
                             width: mark, height: mark))

        line("Dejima", font: font(32, .bold, .wordmark), color: Palette.ink,
             top: 100, width: canvas.width, canvas: canvas)
        line(version, font: font(11), color: Palette.faint,
             top: 138, width: canvas.width, canvas: canvas)

        line("打开与你的系统相符的那个文件夹", font: font(13, .medium, .chinese), color: Palette.muted,
             top: 172, width: canvas.width, canvas: canvas)
        line("Open the folder that matches your macOS", font: font(12), color: Palette.muted,
             top: 196, width: canvas.width, canvas: canvas)
        line("お使いの macOS に合うフォルダを開いてください", font: font(12, .regular, .japanese), color: Palette.muted,
             top: 218, width: canvas.width, canvas: canvas)

        // A card per build, so the two read as a choice between two things
        // rather than as two loose icons. The folder's own name carries the
        // version range; the caption inside says what the range means.
        for (slot, chinese, english) in [
            (Root.newer, "系统是 macOS 26 或更新", "macOS 26 and later"),
            (Root.older, "系统是 macOS 15 到 25", "macOS 15 through 25"),
        ] {
            let left = slot.x - Root.slotWidth / 2
            frame(top: 238, left: left, width: Root.slotWidth, height: 172, canvas: canvas,
                  fill: Palette.card, stroke: Palette.rule)
            line(chinese, font: font(12, .medium, .chinese), color: Palette.ink,
                 top: 364, left: left, width: Root.slotWidth, canvas: canvas)
            line(english, font: font(11), color: Palette.faint,
                 top: 384, left: left, width: Root.slotWidth, canvas: canvas)
        }

        // Stops short of the Read Me in the corner.
        Palette.rule.setFill()
        CGRect(x: 60, y: canvas.height - 430, width: 440, height: 1).fill()

        for (top, text, lineFont) in [
            (CGFloat(448), "不确定是哪个版本：苹果菜单 → 关于本机", font(11, .regular, .chinese)),
            (CGFloat(467), "Not sure which macOS you have? Apple menu → About This Mac", font(11)),
            (CGFloat(486), "バージョンの確認: アップルメニュー → このMacについて", font(11, .regular, .japanese)),
        ] {
            line(text, font: lineFont, color: Palette.faint, alignment: .left,
                 top: top, left: 60, width: 440, canvas: canvas)
        }
    }

    try write("folder", Build.size) { canvas in
        line("把 Dejima 拖到 Applications", font: font(17, .semibold, .chinese), color: Palette.ink,
             top: 40, width: canvas.width, canvas: canvas)
        line("Drag Dejima onto Applications", font: font(12), color: Palette.muted,
             top: 74, width: canvas.width, canvas: canvas)
        line("Dejima を Applications にドラッグ", font: font(12, .regular, .japanese), color: Palette.muted,
             top: 95, width: canvas.width, canvas: canvas)

        // A dashed target around the Applications alias: the arrow says to
        // drag, this says how far.
        frame(top: Build.applications.y - 74, left: Build.applications.x - 82,
              width: 164, height: 156, canvas: canvas,
              fill: Palette.card,
              stroke: Palette.accent.withAlphaComponent(0.55), dashed: true)

        // An arrow across the gap, short enough that neither the icons nor
        // the target ever sit on it.
        let start = Build.app.x + 66
        let end = Build.applications.x - 88
        let y = canvas.height - Build.app.y
        let head: CGFloat = 13

        Palette.accent.setStroke()
        let shaft = NSBezierPath()
        shaft.lineWidth = 3
        shaft.lineCapStyle = .round
        shaft.move(to: CGPoint(x: start, y: y))
        shaft.line(to: CGPoint(x: end - head + 2, y: y))
        shaft.stroke()

        Palette.accent.setFill()
        let tip = NSBezierPath()
        tip.move(to: CGPoint(x: end, y: y))
        tip.line(to: CGPoint(x: end - head, y: y + head * 0.72))
        tip.line(to: CGPoint(x: end - head, y: y - head * 0.72))
        tip.close()
        tip.fill()

        line("装错了也不要紧：系统版本不够时 macOS 会直接拒绝启动", font: font(11, .regular, .chinese),
             color: Palette.faint, top: 296, width: canvas.width, canvas: canvas)
        line("Picking the wrong build is harmless — macOS just refuses to launch it",
             font: font(11), color: Palette.faint, top: 316, width: canvas.width, canvas: canvas)
    }
}

// MARK: - .DS_Store

/// A .DS_Store, which is a B-tree in a buddy allocator, holding one record
/// per (file name, four-letter property) pair.
///
/// Only a fraction of the format is implemented, and only as much as Finder
/// needs to read back: a single leaf node holding every record, three blocks,
/// no rebalancing, no updates in place. Anything more would be building a
/// database to write one page.
struct DSStore {
    enum Value {
        case blob(Data)
        case long(UInt32)
    }

    private var records: [(name: String, code: String, value: Value)] = []

    mutating func set(_ name: String, _ code: String, _ value: Value) {
        records.append((name, code, value))
    }

    mutating func set(_ name: String, _ code: String, plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        set(name, code, .blob(data))
    }

    /// How a directory's own window looks. Note whose file this goes in: a
    /// folder's window settings are kept by its *parent*, filed under the
    /// folder's name. Only the icon positions live in the folder itself. The
    /// volume's own window is the "." entry of the .DS_Store at its root.
    mutating func window(_ name: String, size: CGSize, iconSize: CGFloat, background: URL) throws {
        try set(name, "bwsp", plist: windowSettings(size: size))
        try set(name, "icvp", plist: iconViewSettings(iconSize: iconSize, background: background))
        set(name, "vSrn", .long(1))
    }

    /// Finder's icon position record: a centre point, then six bytes that are
    /// always these six bytes.
    mutating func place(_ name: String, at point: CGPoint) {
        var data = Data()
        data.append(uint32: UInt32(point.x))
        data.append(uint32: UInt32(point.y))
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00])
        set(name, "Iloc", .blob(data))
    }

    func write(to url: URL) throws {
        // Finder looks records up by binary search, so they have to be in the
        // order it would have put them in: by name, case-insensitively, then
        // by property code.
        let sorted = records.sorted { a, b in
            let left = a.name.lowercased(), right = b.name.lowercased()
            if left != right { return left < right }
            return a.code < b.code
        }

        var node = Data()
        node.append(uint32: 0)  // a leaf: no child pointers
        node.append(uint32: UInt32(sorted.count))
        for record in sorted {
            let name = Array(record.name.utf16)
            node.append(uint32: UInt32(name.count))
            for unit in name { node.append(uint16: unit) }
            node.append(contentsOf: Array(record.code.utf8))
            switch record.value {
            case .blob(let data):
                node.append(contentsOf: Array("blob".utf8))
                node.append(uint32: UInt32(data.count))
                node.append(data)
            case .long(let value):
                node.append(contentsOf: Array("long".utf8))
                node.append(uint32: value)
            }
        }

        // Three blocks: the allocator's own bookkeeping, the B-tree header,
        // and the one node. Addresses pack the block's size into the low five
        // bits, and a block's bytes start four into the file from its offset.
        let headerBlock = (offset: UInt32(0), size: UInt32(32))
        let treeBlock = (offset: UInt32(0x40), size: UInt32(32))
        let nodeExponent = max(10, UInt32(64 - UInt64(node.count + 8).leadingZeroBitCount))
        let nodeBlock = (offset: UInt32(1) << nodeExponent, size: UInt32(1) << nodeExponent)
        let bookExponent = UInt32(11)
        let bookOffset = (nodeBlock.offset + nodeBlock.size + 0x7FF) & ~UInt32(0x7FF)
        let bookBlock = (offset: bookOffset, size: UInt32(1) << bookExponent)

        func address(_ block: (offset: UInt32, size: UInt32)) -> UInt32 {
            block.offset | UInt32(block.size.trailingZeroBitCount)
        }
        let blocks = [bookBlock, treeBlock, nodeBlock]

        var tree = Data()
        tree.append(uint32: 2)     // the node is block 2
        tree.append(uint32: 0)     // …and the only level
        tree.append(uint32: UInt32(sorted.count))
        tree.append(uint32: 1)     // …and the only node
        tree.append(uint32: 0x1000)

        var book = Data()
        book.append(uint32: UInt32(blocks.count))
        book.append(uint32: 0)
        for block in blocks { book.append(uint32: address(block)) }
        book.append(Data(count: (256 - blocks.count) * 4))
        book.append(uint32: 1)     // one directory: the B-tree
        book.append(contentsOf: [4])
        book.append(contentsOf: Array("DSDB".utf8))
        book.append(uint32: 1)
        for list in Self.freeLists(allocated: [headerBlock, treeBlock, nodeBlock, bookBlock]) {
            book.append(uint32: UInt32(list.count))
            for offset in list { book.append(uint32: offset) }
        }
        guard book.count <= Int(bookBlock.size) else { fail("the block table outgrew its block") }

        var file = Data(count: Int(bookBlock.offset + 4) + Int(bookBlock.size))
        file.replaceSubrange(0..<4, with: [0, 0, 0, 1])
        file.replaceSubrange(4..<8, with: Array("Bud1".utf8))
        file.write(uint32: bookBlock.offset, at: 8)
        file.write(uint32: UInt32(book.count), at: 12)
        file.write(uint32: bookBlock.offset, at: 16)
        file.write(uint32: address(nodeBlock), at: 20)
        file.replaceSubrange(Int(treeBlock.offset + 4)..<Int(treeBlock.offset + 4) + tree.count, with: tree)
        file.replaceSubrange(Int(nodeBlock.offset + 4)..<Int(nodeBlock.offset + 4) + node.count, with: node)
        file.replaceSubrange(Int(bookBlock.offset + 4)..<Int(bookBlock.offset + 4) + book.count, with: book)
        try file.write(to: url)
    }

    /// The allocator keeps, for each power of two from 32 bytes up, the blocks
    /// of that size that are free. A block is listed only if its buddy is in
    /// use — two free buddies are one free block of the next size up.
    private static func freeLists(allocated: [(offset: UInt32, size: UInt32)]) -> [[UInt32]] {
        var lists = [[UInt32]](repeating: [], count: 32)

        func isFree(_ offset: UInt64, _ size: UInt64) -> Bool {
            !allocated.contains { UInt64($0.offset) < offset + size && offset < UInt64($0.offset) + UInt64($0.size) }
        }

        /// Returns whether the whole region is free, filling in the lists for
        /// the free parts of a region that isn't.
        @discardableResult
        func walk(_ offset: UInt64, _ exponent: Int) -> Bool {
            let size = UInt64(1) << exponent
            if isFree(offset, size) { return true }
            guard exponent > 5 else { return false }
            let half = size / 2
            let left = walk(offset, exponent - 1)
            let right = walk(offset + half, exponent - 1)
            if left { lists[exponent - 1].append(UInt32(offset)) }
            if right { lists[exponent - 1].append(UInt32(offset + half)) }
            return false
        }
        walk(0, 31)
        return lists
    }
}

extension Data {
    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                            UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func write(uint32 value: UInt32, at index: Int) {
        replaceSubrange(index..<index + 4, with: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                                                  UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}

// MARK: - Window settings

/// Finder wants the background image as an alias record — the pre-bookmark
/// kind that no framework will make for you any more. The Apple Event manager
/// still coerces a file URL into one, which is the last supported way to get
/// the bytes.
func aliasRecord(for url: URL) -> Data {
    guard let alias = NSAppleEventDescriptor(fileURL: url).coerce(toDescriptorType: DescType(typeAlias)) else {
        fail("could not make an alias record for \(url.path)")
    }
    return alias.data
}

func windowSettings(size: CGSize) -> [String: Any] {
    // Screen coordinates, bottom-left origin. Finder moves the window if it
    // doesn't fit, so this is only where it prefers to open.
    [
        "WindowBounds": "{{180, 220}, {\(Int(size.width)), \(Int(size.height))}}",
        "ShowSidebar": false,
        "ShowToolbar": false,
        "ShowStatusBar": false,
        "ShowPathbar": false,
        "ShowTabView": false,
        "ContainerShowSidebar": false,
        "SidebarWidth": 0,
    ]
}

func iconViewSettings(iconSize: CGFloat, background: URL) -> [String: Any] {
    [
        "viewOptionsVersion": 1,
        "backgroundType": 2,  // 0 default, 1 colour, 2 picture
        "backgroundImageAlias": aliasRecord(for: background),
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "arrangeBy": "none",
        "iconSize": Double(iconSize),
        "textSize": 12.0,
        "labelOnBottom": true,
        "showIconPreview": true,
        "showItemInfo": false,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    ]
}

func installLayout(volume: URL, newerFolder: String, olderFolder: String, icon: NSImage) throws {
    // The mounted disk answers to the app's own icon rather than the generic
    // white one, in the sidebar and on the desktop.
    NSWorkspace.shared.setIcon(icon, forFile: volume.path)

    let backgrounds = volume.appendingPathComponent(".background")
    let buildFolders = [newerFolder, olderFolder]

    var root = DSStore()
    try root.window(".", size: Root.size, iconSize: Root.iconSize,
                    background: backgrounds.appendingPathComponent("root.tiff"))
    root.place(newerFolder, at: Root.newer)
    root.place(olderFolder, at: Root.older)
    root.place("Read Me.txt", at: Root.readMe)
    for folder in buildFolders {
        try root.window(folder, size: Build.size, iconSize: Build.iconSize,
                        background: backgrounds.appendingPathComponent("folder.tiff"))
    }
    try root.write(to: volume.appendingPathComponent(".DS_Store"))

    for folder in buildFolders {
        var build = DSStore()
        build.place("Dejima.app", at: Build.app)
        build.place("Applications", at: Build.applications)
        try build.write(to: volume.appendingPathComponent(folder).appendingPathComponent(".DS_Store"))
    }
}

// MARK: - Entry point

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadIcon(_ path: String) -> NSImage {
    guard let icon = NSImage(contentsOfFile: path) else { fail("could not read the icon at \(path)") }
    return icon
}

let arguments = CommandLine.arguments
do {
    switch arguments.dropFirst().first {
    case "art" where arguments.count == 5:
        try drawArt(into: URL(fileURLWithPath: arguments[2], isDirectory: true),
                    version: arguments[3],
                    icon: loadIcon(arguments[4]))
    case "layout" where arguments.count == 6:
        try installLayout(volume: URL(fileURLWithPath: arguments[2], isDirectory: true),
                          newerFolder: arguments[3],
                          olderFolder: arguments[4],
                          icon: loadIcon(arguments[5]))
    default:
        FileHandle.standardError.write(Data("""
            usage: dmg-window.swift art <output directory> <version> <icon>
                   dmg-window.swift layout <mounted volume> <newer folder> <older folder> <icon>

            """.utf8))
        exit(2)
    }
} catch {
    fail("\(error)")
}
