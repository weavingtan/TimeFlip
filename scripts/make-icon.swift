import AppKit
import Foundation

// 用 Command Line Tools 直接画出 TimeFlip 的 App 图标（1024px 主图 → 由调用方转成 .icns）。
// 造型与挂件一致：墨色圆角底 + 两张纸白翻页卡 + 中缝。
// 用法: swift scripts/make-icon.swift <输出目录>

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/icon")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let ink = color(0x17181C)

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
    return base
}

/// 把一段文字按视觉中心画在 rect 里。
func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.boundingRect(with: NSSize(width: canvas, height: canvas), options: [.usesLineFragmentOrigin])
    string.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("cannot create graphics context\n".utf8))
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

// 底：墨色圆角方块（macOS 图标网格：824 宽、185 圆角、居中）+ 投影
let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let body = roundedPath(bodyRect, radius: 185)

NSGraphicsContext.saveGraphicsState()
let bodyShadow = NSShadow()
bodyShadow.shadowColor = color(0x000000, 0.34)
bodyShadow.shadowBlurRadius = 34
bodyShadow.shadowOffset = NSSize(width: 0, height: -14)
bodyShadow.set()
NSGradient(starting: color(0x2F313A), ending: color(0x121317))?.draw(in: body, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 顶部一道极淡的高光，让方块有实体感
NSGraphicsContext.saveGraphicsState()
body.addClip()
let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: bodyRect.minX, y: bodyRect.maxY - 3))
highlight.line(to: NSPoint(x: bodyRect.maxX, y: bodyRect.maxY - 3))
highlight.lineWidth = 6
color(0xFFFFFF, 0.10).setStroke()
highlight.stroke()
NSGraphicsContext.restoreGraphicsState()

// 两张翻页卡
let cardSize = NSSize(width: 280, height: 420)
let gap: CGFloat = 48
let totalWidth = cardSize.width * 2 + gap
let cardY = canvas / 2 - cardSize.height / 2
let digits = ["2", "5"]
let digitFont = roundedFont(size: 356, weight: .bold)

for index in 0..<2 {
    let x = canvas / 2 - totalWidth / 2 + CGFloat(index) * (cardSize.width + gap)
    let cardRect = NSRect(x: x, y: cardY, width: cardSize.width, height: cardSize.height)
    let card = roundedPath(cardRect, radius: 34)

    // 卡面 + 投影
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = color(0x000000, 0.30)
    cardShadow.shadowBlurRadius = 20
    cardShadow.shadowOffset = NSSize(width: 0, height: -8)
    cardShadow.set()
    color(0xF0F0EA).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    card.addClip()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xE7E7DF))?.draw(in: cardRect, angle: -90)

    // 中缝：一条细凹线 + 下方一点提亮，像上下两张卡叠在一起
    let seamY = cardRect.midY
    color(0x1A1A1A, 0.14).setFill()
    NSRect(x: cardRect.minX, y: seamY - 3, width: cardRect.width, height: 6).fill()
    color(0xFFFFFF, 0.75).setFill()
    NSRect(x: cardRect.minX, y: seamY - 5, width: cardRect.width, height: 2).fill()

    // 上半张卡向内的一点暗部，暗示翻页面的厚度
    NSGradient(starting: color(0x000000, 0.06), ending: color(0x000000, 0))?
        .draw(in: NSRect(x: cardRect.minX, y: cardRect.maxY - 90, width: cardRect.width, height: 90), angle: -90)

    drawCentered(digits[index], font: digitFont, color: ink, in: cardRect)
    NSGraphicsContext.restoreGraphicsState()
}

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("png encode failed\n".utf8))
    exit(1)
}

let masterURL = outputDir.appendingPathComponent("icon-1024.png")
try png.write(to: masterURL)
print("wrote \(masterURL.path)")
