import AppKit
import Foundation

private enum IconKind {
    case menu
    case install
    case uninstall
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

private func line(_ start: NSPoint, _ end: NSPoint, width: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.move(to: start)
    path.line(to: end)
    path.stroke()
}

private func drawIcon(kind: IconKind, pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.025, dy: size * 0.025), xRadius: size * 0.22, yRadius: size * 0.22)
    let colors: [NSColor]
    switch kind {
    case .menu:
        colors = [color(0.08, 0.43, 0.35), color(0.04, 0.20, 0.28)]
    case .install:
        colors = [color(0.10, 0.47, 0.42), color(0.05, 0.23, 0.34)]
    case .uninstall:
        colors = [color(0.36, 0.28, 0.22), color(0.19, 0.17, 0.20)]
    }
    NSGradient(colors: colors)!.draw(in: background, angle: -45)

    let wheelCenter = NSPoint(x: size * 0.47, y: size * 0.56)
    let wheelRadius = size * 0.28
    let wheel = NSBezierPath(ovalIn: NSRect(
        x: wheelCenter.x - wheelRadius,
        y: wheelCenter.y - wheelRadius,
        width: wheelRadius * 2,
        height: wheelRadius * 2
    ))
    wheel.lineWidth = size * 0.055
    color(0.96, 0.97, 0.91).setStroke()
    wheel.stroke()

    let hubRadius = size * 0.065
    let hub = NSBezierPath(ovalIn: NSRect(
        x: wheelCenter.x - hubRadius,
        y: wheelCenter.y - hubRadius,
        width: hubRadius * 2,
        height: hubRadius * 2
    ))
    color(0.96, 0.97, 0.91).setFill()
    hub.fill()
    let spokeStart = size * 0.075
    let spokeEnd = wheelRadius * 0.83
    for angle in [90.0, 210.0, 330.0] {
        let radians = CGFloat(angle * .pi / 180)
        line(
            NSPoint(x: wheelCenter.x + cos(radians) * spokeStart, y: wheelCenter.y + sin(radians) * spokeStart),
            NSPoint(x: wheelCenter.x + cos(radians) * spokeEnd, y: wheelCenter.y + sin(radians) * spokeEnd),
            width: size * 0.045
        )
    }

    if kind != .menu {
        let badgeCenter = NSPoint(x: size * 0.75, y: size * 0.28)
        let badgeRadius = size * 0.17
        let badge = NSBezierPath(ovalIn: NSRect(
            x: badgeCenter.x - badgeRadius,
            y: badgeCenter.y - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        ))
        (kind == .install ? color(0.45, 0.78, 0.35) : color(0.88, 0.31, 0.25)).setFill()
        badge.fill()

        if kind == .install {
            line(NSPoint(x: badgeCenter.x, y: badgeCenter.y + size * 0.075), NSPoint(x: badgeCenter.x, y: badgeCenter.y - size * 0.045), width: size * 0.035)
            line(NSPoint(x: badgeCenter.x - size * 0.065, y: badgeCenter.y + size * 0.005), NSPoint(x: badgeCenter.x, y: badgeCenter.y - size * 0.06), width: size * 0.035)
            line(NSPoint(x: badgeCenter.x + size * 0.065, y: badgeCenter.y + size * 0.005), NSPoint(x: badgeCenter.x, y: badgeCenter.y - size * 0.06), width: size * 0.035)
            line(NSPoint(x: badgeCenter.x - size * 0.075, y: badgeCenter.y - size * 0.095), NSPoint(x: badgeCenter.x + size * 0.075, y: badgeCenter.y - size * 0.095), width: size * 0.035)
        } else {
            color(1, 1, 1).setFill()
            let bin = NSBezierPath(roundedRect: NSRect(x: badgeCenter.x - size * 0.055, y: badgeCenter.y - size * 0.07, width: size * 0.11, height: size * 0.12), xRadius: size * 0.012, yRadius: size * 0.012)
            bin.fill()
            line(NSPoint(x: badgeCenter.x - size * 0.075, y: badgeCenter.y + size * 0.065), NSPoint(x: badgeCenter.x + size * 0.075, y: badgeCenter.y + size * 0.065), width: size * 0.035)
            line(NSPoint(x: badgeCenter.x - size * 0.035, y: badgeCenter.y + size * 0.095), NSPoint(x: badgeCenter.x + size * 0.035, y: badgeCenter.y + size * 0.095), width: size * 0.025)
        }
    }

    image.unlockFocus()
    let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return representation.representation(using: .png, properties: [:])!
}

@main
struct BuildIcons {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: BuildIcons <output-directory>\n", stderr)
            exit(2)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let iconSizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for (name, kind) in [("Menu", IconKind.menu), ("Install", .install), ("Uninstall", .uninstall)] {
            let iconset = root.appendingPathComponent("\(name).iconset", isDirectory: true)
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for (fileName, pixels) in iconSizes {
                try drawIcon(kind: kind, pixels: pixels).write(to: iconset.appendingPathComponent(fileName))
            }
        }
    }
}