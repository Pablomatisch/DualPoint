#!/usr/bin/env swift
import AppKit
import Foundation

// Generates DualPoint's application icon (iconset + 1024px PNG).
// Usage: swift Scripts/make-icons.swift

let outRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = outRoot.appendingPathComponent("Resources/AppIcon.iconset")
let previewURL = outRoot.appendingPathComponent("Resources/AppIcon.png")

func cursorPath(in rect: CGRect) -> NSBezierPath {
    // Classic pointer silhouette, tip at top-left, drawn in a top-left origin space.
    let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
    let p = NSBezierPath()
    p.move(to: CGPoint(x: x, y: y))
    p.line(to: CGPoint(x: x, y: y + h * 0.82))
    p.line(to: CGPoint(x: x + w * 0.23, y: y + h * 0.61))
    p.line(to: CGPoint(x: x + w * 0.39, y: y + h * 0.98))
    p.line(to: CGPoint(x: x + w * 0.54, y: y + h * 0.92))
    p.line(to: CGPoint(x: x + w * 0.38, y: y + h * 0.56))
    p.line(to: CGPoint(x: x + w * 0.69, y: y + h * 0.56))
    p.close()
    return p
}

func render(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current else { return image }
    ctx.imageInterpolation = .high
    // Flip to a top-left origin coordinate space.
    let t = NSAffineTransform()
    t.translateX(by: 0, yBy: s)
    t.scaleX(by: 1, yBy: -1)
    t.concat()

    let inset = s * 0.09765625 // 100/1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.1806640625 // 185/1024
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Deep, quiet background with a subtle vertical gradient.
    let top = NSColor(srgbRed: 0.075, green: 0.090, blue: 0.145, alpha: 1.0)
    let bottom = NSColor(srgbRed: 0.125, green: 0.155, blue: 0.230, alpha: 1.0)
    NSGradient(starting: bottom, ending: top)?.draw(in: bodyPath, angle: 90)

    // Soft top-left light.
    ctx.saveGraphicsState()
    bodyPath.addClip()
    let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.55, green: 0.68, blue: 1.0, alpha: 0.16),
        NSColor(srgbRed: 0.55, green: 0.68, blue: 1.0, alpha: 0.0),
    ])
    glow?.draw(fromCenter: CGPoint(x: body.minX + body.width * 0.26, y: body.minY + body.height * 0.20),
               radius: 0, toCenter: CGPoint(x: body.minX + body.width * 0.26, y: body.minY + body.height * 0.20),
               radius: body.width * 0.62, options: [])
    ctx.restoreGraphicsState()

    // Hairline edge.
    NSColor.white.withAlphaComponent(0.10).setStroke()
    bodyPath.lineWidth = max(1, s / 512)
    bodyPath.stroke()

    // Two cursor positions: one cool white (front), one electric blue (behind).
    let unit = s / 1024.0
    let blue = NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1.0)
    let white = NSColor(srgbRed: 0.965, green: 0.975, blue: 1.0, alpha: 1.0)

    let rear = cursorPath(in: CGRect(x: 452 * unit, y: 402 * unit, width: 336 * unit, height: 438 * unit))
    NSColor.black.withAlphaComponent(0.22).setFill()
    let rearShadow = rear.copy() as! NSBezierPath
    rearShadow.transform(using: AffineTransform(translationByX: 0, byY: 10 * unit))
    rearShadow.fill()
    blue.setFill()
    rear.fill()

    let front = cursorPath(in: CGRect(x: 270 * unit, y: 224 * unit, width: 336 * unit, height: 438 * unit))
    NSColor.black.withAlphaComponent(0.30).setFill()
    let frontShadow = front.copy() as! NSBezierPath
    frontShadow.transform(using: AffineTransform(translationByX: 0, byY: 12 * unit))
    frontShadow.fill()
    white.setFill()
    front.fill()

    // A small blue notch cut into the front arrow to tie the two marks together.
    ctx.restoreGraphicsState()
    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let master = render(size: 1024)
if let data = pngData(master, pixelSize: 1024) {
    try data.write(to: previewURL)
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    let img = render(size: px)
    if let data = pngData(img, pixelSize: px) {
        try data.write(to: iconsetURL.appendingPathComponent("\(name).png"))
    }
}
print("Wrote \(iconsetURL.path) and \(previewURL.path)")
