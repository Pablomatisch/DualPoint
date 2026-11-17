#!/usr/bin/env swift
// Generates the public README and DMG artwork from the real brand tokens and
// the offscreen screenshots produced by SnapshotRunner. No invented UI.
//
// Usage:
//   swift Scripts/make-release-assets.swift <snapshot-dir> <output-dir>

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: make-release-assets <snapshot-dir> <output-dir>\n", stderr)
    exit(2)
}
let snapshotDir = URL(fileURLWithPath: args[1], isDirectory: true)
let outputDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// MARK: - Brand (mirrors Sources/DualPoint/Views/Brand.swift)

let accent = NSColor(srgbRed: 0.46, green: 0.44, blue: 1.00, alpha: 1)
let violet = NSColor(srgbRed: 0.66, green: 0.40, blue: 1.00, alpha: 1)
let cyan = NSColor(srgbRed: 0.24, green: 0.80, blue: 1.00, alpha: 1)
let textPrimary = NSColor.white.withAlphaComponent(0.95)
let textSecondary = NSColor.white.withAlphaComponent(0.64)
let textTertiary = NSColor.white.withAlphaComponent(0.40)

let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/AppIcon.png")
let appIcon = NSImage(contentsOf: iconURL)

// MARK: - Drawing helpers

private final class CanvasView: NSView {
    let logicalSize: NSSize
    let body: (CGFloat, CGFloat) -> Void

    init(logicalSize: NSSize, body: @escaping (CGFloat, CGFloat) -> Void) {
        self.logicalSize = logicalSize
        self.body = body
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: logicalSize.width,
            height: logicalSize.height
        ))
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // The view's bounds use logical points; bitmapImageRepForCachingDisplay
        // captures at the display's 2x backing scale for retina output.
        NSGraphicsContext.current?.imageInterpolation = .high
        body(logicalSize.width, logicalSize.height)
    }
}

// The view uses logical points; bitmapImageRepForCachingDisplay captures at the
// display's 2x backing scale, producing 2400px-wide retina artwork.
func render(width: Int, height: Int, _ body: @escaping (CGFloat, CGFloat) -> Void) -> Data? {
    let view = CanvasView(
        logicalSize: NSSize(width: width, height: height),
        body: body
    )
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

func background(_ w: CGFloat, _ h: CGFloat) {
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.035, green: 0.035, blue: 0.075, alpha: 1),
        NSColor(srgbRed: 0.075, green: 0.070, blue: 0.145, alpha: 1)
    ])
    gradient?.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
}

func glow(center: CGPoint, radius: CGFloat, color: NSColor) {
    let gradient = NSGradient(colors: [color, color.withAlphaComponent(0)])
    gradient?.draw(
        fromCenter: center, radius: 0,
        toCenter: center, radius: radius,
        options: []
    )
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if let fill { fill.setFill(); path.fill() }
    if let stroke { stroke.setStroke(); path.lineWidth = width; path.stroke() }
}

func label(
    _ string: String,
    _ rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = textPrimary,
    align: NSTextAlignment = .left
) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    NSString(string: string).draw(in: rect, withAttributes: attributes)
}

func capsule(_ rect: NSRect, text: String) {
    rounded(rect, radius: rect.height / 2, fill: NSColor.white.withAlphaComponent(0.07),
            stroke: NSColor.white.withAlphaComponent(0.12))
    label(text, rect.insetBy(dx: 12, dy: 0), size: 13, weight: .medium,
          color: textSecondary, align: .center)
}

func drawIcon(_ rect: NSRect) {
    guard let appIcon else { return }
    let shadow = NSShadow()
    shadow.shadowColor = accent.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = CGSize(width: 0, height: 4)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    appIcon.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func drawScreenshot(named name: String, in rect: NSRect, corner: CGFloat = 22) {
    guard let image = NSImage(contentsOf: snapshotDir.appendingPathComponent(name)) else { return }
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = CGSize(width: 0, height: 10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.clear.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let aspect = image.size.width / image.size.height
    let targetAspect = rect.width / rect.height
    var drawRect = rect
    if aspect > targetAspect {
        let h = rect.width / aspect
        drawRect = NSRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
    } else {
        let w = rect.height * aspect
        drawRect = NSRect(x: rect.minX + (rect.width - w) / 2, y: rect.minY, width: w, height: rect.height)
    }
    image.draw(in: drawRect)
    NSGraphicsContext.restoreGraphicsState()

    path.lineWidth = 1
    NSColor.white.withAlphaComponent(0.14).setStroke()
    path.stroke()
}

func cursorGlyph(at point: CGPoint, size: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: point.x, y: point.y))
    p.line(to: CGPoint(x: point.x, y: point.y + size * 0.82))
    p.line(to: CGPoint(x: point.x + size * 0.23, y: point.y + size * 0.61))
    p.line(to: CGPoint(x: point.x + size * 0.39, y: point.y + size * 0.98))
    p.line(to: CGPoint(x: point.x + size * 0.54, y: point.y + size * 0.92))
    p.line(to: CGPoint(x: point.x + size * 0.38, y: point.y + size * 0.56))
    p.line(to: CGPoint(x: point.x + size * 0.69, y: point.y + size * 0.56))
    p.close()
    color.setFill()
    p.fill()
}

func displayCard(_ rect: NSRect, title: String, detail: String, accentColor: NSColor, cursor: CGPoint?) {
    rounded(rect, radius: 18,
            fill: NSColor.white.withAlphaComponent(0.055),
            stroke: NSColor.white.withAlphaComponent(0.10))
    let screen = rect.insetBy(dx: 24, dy: 22)
    rounded(NSRect(x: screen.minX, y: screen.minY + 20, width: screen.width, height: screen.height - 34),
            radius: 10, fill: NSColor.black.withAlphaComponent(0.28),
            stroke: accentColor.withAlphaComponent(0.42))
    label(title, NSRect(x: rect.minX + 24, y: rect.minY + 14, width: rect.width - 48, height: 20),
          size: 13, weight: .semibold, color: textSecondary)
    label(detail, NSRect(x: rect.minX + 24, y: rect.maxY - 30, width: rect.width - 48, height: 18),
          size: 12, color: textTertiary)
    if let cursor { cursorGlyph(at: cursor, size: 28, color: accentColor) }
}

func write(_ data: Data?, _ name: String) {
    guard let data else { fputs("failed: \(name)\n", stderr); exit(1) }
    do { try data.write(to: outputDir.appendingPathComponent(name)) }
    catch { fputs("\(error)\n", stderr); exit(1) }
    print("wrote \(name)")
}

// MARK: - Artwork

write(render(width: 1200, height: 600) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 930, y: 220), radius: 470, color: violet.withAlphaComponent(0.30))
    glow(center: CGPoint(x: 220, y: 520), radius: 320, color: accent.withAlphaComponent(0.12))
    drawIcon(NSRect(x: 72, y: 62, width: 62, height: 62))
    label("DUALPOINT", NSRect(x: 150, y: 80, width: 300, height: 22),
          size: 13, weight: .semibold, color: textTertiary)
    label("Two devices.\nTwo places.", NSRect(x: 72, y: 156, width: 530, height: 130),
          size: 46, weight: .bold)
    label("One real cursor. Every device returns to the spot you left it.",
          NSRect(x: 72, y: 302, width: 510, height: 60), size: 19, color: textSecondary)
    capsule(NSRect(x: 72, y: 388, width: 244, height: 36), text: "macOS 13+  ·  Menu bar utility")
    drawScreenshot(named: "panel.png", in: NSRect(x: 650, y: 58, width: 480, height: 484))
    label("No second cursor. No account. No network access.",
          NSRect(x: 72, y: 534, width: 540, height: 22), size: 13, color: textTertiary)
}, "hero.png")

write(render(width: 1200, height: 420) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 1040, y: 60), radius: 380, color: accent.withAlphaComponent(0.16))
    label("THE PROBLEM", NSRect(x: 72, y: 44, width: 400, height: 20),
          size: 12, weight: .semibold, color: accent)
    label("Your cursor gets left behind.", NSRect(x: 72, y: 74, width: 700, height: 46),
          size: 31, weight: .bold)
    label("You move the mouse to the external display. Then you switch back to the trackpad — and the cursor is somewhere else.",
          NSRect(x: 72, y: 124, width: 1040, height: 44), size: 16, color: textSecondary)
    displayCard(NSRect(x: 72, y: 194, width: 470, height: 178),
                title: "EXTERNAL DISPLAY", detail: "Mouse was here", accentColor: cyan,
                cursor: CGPoint(x: 450, y: 258))
    displayCard(NSRect(x: 658, y: 194, width: 470, height: 178),
                title: "MACBOOK DISPLAY", detail: "Trackpad takes over here", accentColor: accent,
                cursor: CGPoint(x: 1036, y: 258))
    label("switch devices", NSRect(x: 530, y: 258, width: 140, height: 24),
          size: 12, color: textTertiary, align: .center)
}, "problem.png")

write(render(width: 1200, height: 420) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 1090, y: 350), radius: 420, color: violet.withAlphaComponent(0.18))
    label("HOW IT WORKS", NSRect(x: 72, y: 44, width: 400, height: 20),
          size: 12, weight: .semibold, color: accent)
    label("Three steps. Then it just works.", NSRect(x: 72, y: 74, width: 760, height: 46),
          size: 31, weight: .bold)
    let steps = [
        ("1", "Connect", "DualPoint detects your trackpad,\nmice and external displays."),
        ("2", "Assign", "Choose a home display for each\ndevice. Optional, but helpful."),
        ("3", "Switch", "Each device returns to its own\nlast cursor position.")
    ]
    for (index, step) in steps.enumerated() {
        let x = CGFloat(72 + index * 366)
        let card = NSRect(x: x, y: 178, width: 340, height: 190)
        rounded(card, radius: 18, fill: NSColor.white.withAlphaComponent(0.055),
                stroke: NSColor.white.withAlphaComponent(0.10))
        rounded(NSRect(x: x + 22, y: 200, width: 40, height: 40), radius: 20,
                fill: accent.withAlphaComponent(0.20), stroke: accent.withAlphaComponent(0.55))
        label(step.0, NSRect(x: x + 22, y: 209, width: 40, height: 24),
              size: 16, weight: .bold, color: textPrimary, align: .center)
        label(step.1, NSRect(x: x + 22, y: 258, width: 296, height: 28),
              size: 20, weight: .semibold)
        label(step.2, NSRect(x: x + 22, y: 292, width: 296, height: 62),
              size: 14, color: textSecondary)
    }
}, "how-it-works.png")

write(render(width: 1200, height: 300) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 1080, y: 250), radius: 340, color: accent.withAlphaComponent(0.14))
    label("INSTALLATION", NSRect(x: 72, y: 34, width: 400, height: 18),
          size: 12, weight: .semibold, color: accent)
    let steps = [
        ("1", "Download", "the .dmg from Releases"),
        ("2", "Drag", "DualPoint to Applications"),
        ("3", "Open", "and allow Input Monitoring"),
        ("4", "Done", "the setup assistant guides you")
    ]
    for (index, step) in steps.enumerated() {
        let x = CGFloat(72 + index * 278)
        rounded(NSRect(x: x, y: 92, width: 256, height: 150), radius: 16,
                fill: NSColor.white.withAlphaComponent(0.05),
                stroke: NSColor.white.withAlphaComponent(0.10))
        rounded(NSRect(x: x + 18, y: 112, width: 34, height: 34), radius: 17, fill: accent)
        label(step.0, NSRect(x: x + 18, y: 120, width: 34, height: 20),
              size: 15, weight: .bold, align: .center)
        label(step.1, NSRect(x: x + 18, y: 160, width: 220, height: 26),
              size: 18, weight: .semibold)
        label(step.2, NSRect(x: x + 18, y: 190, width: 220, height: 42),
              size: 13, color: textSecondary)
    }
}, "install.png")

write(render(width: 1280, height: 640) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 1040, y: 180), radius: 420, color: violet.withAlphaComponent(0.26))
    drawIcon(NSRect(x: 76, y: 92, width: 92, height: 92))
    label("DualPoint", NSRect(x: 76, y: 214, width: 540, height: 74),
          size: 54, weight: .bold)
    label("Give every pointing device its own cursor position.",
          NSRect(x: 76, y: 302, width: 520, height: 80), size: 24, color: textSecondary)
    label("macOS 13+  ·  Private by design", NSRect(x: 76, y: 420, width: 520, height: 26),
          size: 16, color: textTertiary)
    drawScreenshot(named: "panel.png", in: NSRect(x: 720, y: 78, width: 470, height: 474))
}, "social-preview.png")

write(render(width: 660, height: 420) { w, h in
    background(w, h)
    glow(center: CGPoint(x: 130, y: 90), radius: 260, color: accent.withAlphaComponent(0.18))
    drawIcon(NSRect(x: 44, y: 44, width: 86, height: 86))
    label("DualPoint", NSRect(x: 148, y: 68, width: 300, height: 42), size: 30, weight: .bold)
    label("Drag DualPoint into Applications", NSRect(x: 44, y: 158, width: 390, height: 56),
          size: 21, weight: .medium, color: textSecondary)

    // Folder glyph and arrow (no invented application UI).
    let folder = NSBezierPath()
    folder.move(to: CGPoint(x: 462, y: 196))
    folder.line(to: CGPoint(x: 512, y: 196))
    folder.line(to: CGPoint(x: 528, y: 212))
    folder.line(to: CGPoint(x: 600, y: 212))
    folder.line(to: CGPoint(x: 600, y: 318))
    folder.line(to: CGPoint(x: 462, y: 318))
    folder.close()
    accent.withAlphaComponent(0.26).setFill()
    folder.fill()
    accent.withAlphaComponent(0.65).setStroke()
    folder.lineWidth = 2
    folder.stroke()

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 60, y: 300))
    arrow.line(to: CGPoint(x: 430, y: 300))
    arrow.move(to: CGPoint(x: 408, y: 282))
    arrow.line(to: CGPoint(x: 432, y: 300))
    arrow.line(to: CGPoint(x: 408, y: 318))
    accent.setStroke()
    arrow.lineWidth = 3
    arrow.stroke()

    label("Then open it from Applications.", NSRect(x: 44, y: 352, width: 560, height: 26),
          size: 14, color: textTertiary)
}, "dmg-background.png")
