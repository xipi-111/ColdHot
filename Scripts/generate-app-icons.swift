#!/usr/bin/env swift

import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("无法创建绘图上下文")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
let context = graphicsContext.cgContext

context.clear(CGRect(origin: .zero, size: canvasSize))

let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 210, yRadius: 210)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -24), blur: 44, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.12, alpha: 1).setFill()
tile.fill()
context.restoreGState()

tile.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.16, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.27, green: 0.055, blue: 0.08, alpha: 1)
])!.draw(in: tile, angle: 0)

let center = CGPoint(x: 512, y: 440)
let radius: CGFloat = 285
context.setLineCap(.round)
context.setLineWidth(54)

func strokeArc(color: NSColor, start: CGFloat, end: CGFloat) {
    context.setStrokeColor(color.cgColor)
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    context.strokePath()
}

strokeArc(color: NSColor(calibratedRed: 0.08, green: 0.82, blue: 0.98, alpha: 1), start: .pi * 0.08, end: .pi * 0.5)
strokeArc(color: NSColor(calibratedRed: 0.28, green: 0.48, blue: 1.0, alpha: 1), start: .pi * 0.5, end: .pi * 0.92)
strokeArc(color: NSColor(calibratedRed: 1.0, green: 0.46, blue: 0.18, alpha: 1), start: .pi * 0.92, end: .pi * 1.34)
strokeArc(color: NSColor(calibratedRed: 1.0, green: 0.16, blue: 0.28, alpha: 1), start: .pi * 1.34, end: .pi * 1.76)

for index in 0...10 {
    let angle = CGFloat.pi * (0.08 + CGFloat(index) * 0.168)
    let inner = CGPoint(x: center.x + cos(angle) * 220, y: center.y + sin(angle) * 220)
    let outer = CGPoint(x: center.x + cos(angle) * 242, y: center.y + sin(angle) * 242)
    context.setStrokeColor(NSColor.white.withAlphaComponent(index == 5 ? 0.85 : 0.46).cgColor)
    context.setLineWidth(index == 5 ? 12 : 8)
    context.move(to: inner)
    context.addLine(to: outer)
    context.strokePath()
}

let needleAngle = CGFloat.pi * 1.18
let needleTip = CGPoint(x: center.x + cos(needleAngle) * 205, y: center.y + sin(needleAngle) * 205)
context.setStrokeColor(NSColor.white.cgColor)
context.setLineWidth(22)
context.move(to: center)
context.addLine(to: needleTip)
context.strokePath()

let hub = NSBezierPath(ovalIn: NSRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84))
NSColor.white.setFill()
hub.fill()
let hubCore = NSBezierPath(ovalIn: NSRect(x: center.x - 19, y: center.y - 19, width: 38, height: 38))
NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.2, alpha: 1).setFill()
hubCore.fill()

let shine = NSBezierPath(roundedRect: NSRect(x: 188, y: 714, width: 648, height: 54), xRadius: 27, yRadius: 27)
NSColor.white.withAlphaComponent(0.08).setFill()
shine.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码 PNG")
}

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
try png.write(to: outputURL.appendingPathComponent("icon_512x512@2x.png"))
