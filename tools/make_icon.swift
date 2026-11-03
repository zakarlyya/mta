// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift tools/make_icon.swift
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824pt body centered in a 1024pt canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x34343A), ending: color(0x0E0E11))!.draw(in: shape, angle: -90)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "2 min", attributes: [
        .font: roundedFont(250 * s, .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ])
    let titleSize = title.size()
    title.draw(in: NSRect(x: body.minX, y: 470 * s, width: body.width, height: titleSize.height))

    let lines: [(String, UInt32, NSColor)] = [
        ("1", 0xEE352E, .white), ("A", 0x0039A6, .white), ("B", 0xFF6319, .white), ("N", 0xFCCC0A, .black),
    ]
    let diameter = 140 * s
    let gap = 36 * s
    let totalWidth = CGFloat(lines.count) * diameter + CGFloat(lines.count - 1) * gap
    var x = body.midX - totalWidth / 2
    for (letter, fill, textColor) in lines {
        let circle = NSRect(x: x, y: 250 * s, width: diameter, height: diameter)
        color(fill).setFill()
        NSBezierPath(ovalIn: circle).fill()
        let label = NSAttributedString(string: letter, attributes: [
            .font: NSFont.systemFont(ofSize: 96 * s, weight: .bold),
            .foregroundColor: textColor,
        ])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: circle.midX - labelSize.width / 2, y: circle.midY - labelSize.height / 2))
        x += diameter + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let output = resources.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try drawIcon(size: 512).representation(using: .png, properties: [:])!
    .write(to: resources.appendingPathComponent("AppIcon.png"))
print("Wrote \(output.path)")
