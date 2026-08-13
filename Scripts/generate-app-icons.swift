#!/usr/bin/env swift

import AppKit

let scriptURL = URL(fileURLWithPath: #filePath)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let sourceURL = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst(2).first
        ?? projectRoot.appendingPathComponent("Artwork/ColdHot-AppIcon-Fan-Source.png").path
)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("无法读取图标源文件：\(sourceURL.path)")
}

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func pngData(pixelSize: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("无法创建 \(pixelSize)px 绘图上下文")
    }

    let size = CGFloat(pixelSize)
    let scale = size / 1024
    let destination = NSRect(x: 0, y: 0, width: size, height: size)
    let tileRect = NSRect(
        x: 72 * scale,
        y: 72 * scale,
        width: 880 * scale,
        height: 880 * scale
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high
    graphicsContext.cgContext.clear(destination)

    NSBezierPath(
        roundedRect: tileRect,
        xRadius: 196 * scale,
        yRadius: 196 * scale
    ).addClip()
    sourceImage.draw(
        in: destination,
        from: .zero,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("无法编码 \(pixelSize)px PNG")
    }
    return data
}

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for icon in iconFiles {
    try pngData(pixelSize: icon.pixels).write(
        to: outputURL.appendingPathComponent(icon.name),
        options: .atomic
    )
}

print("已生成 \(iconFiles.count) 个克制风扇图标尺寸：\(outputURL.path)")
