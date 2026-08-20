import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DynamicBackgroundTestMedia {
    static func makeTwoFrameGIF(at url: URL) throws {
        try makeTwoFrameGIF(at: url, width: 32, height: 24)
    }

    static func makeOversizedTwoFrameGIF(at url: URL) throws {
        try makeTwoFrameGIF(at: url, width: 2_000, height: 1_000)
    }

    static func makeCancellationGIF(at url: URL) throws {
        let red = try makeSolidImage(red: 1, green: 0, blue: 0, width: 640, height: 480)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1, width: 640, height: 480)
        try writeGIF(
            at: url,
            frames: (0..<120).map { $0.isMultiple(of: 2) ? red : blue },
            delays: Array(repeating: 0.02, count: 120)
        )
    }

    static func makeTransparentGIFWithLogicalBackground(at url: URL) throws {
        try writeTransparentGIF(at: url, includesGlobalColorTable: true)
    }

    static func makeTransparentGIFWithoutLogicalBackground(at url: URL) throws {
        try writeTransparentGIF(at: url, includesGlobalColorTable: false)
    }

    static func extendFile(at url: URL, toByteCount byteCount: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(byteCount))
    }

    private static func makeTwoFrameGIF(at url: URL, width: Int, height: Int) throws {
        let red = try makeSolidImage(red: 1, green: 0, blue: 0, width: width, height: height)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1, width: width, height: height)
        try writeGIF(at: url, frames: [red, blue], delays: [0.10, 0.25])
    }

    private static func writeGIF(at url: URL, frames: [CGImage], delays: [Double]) throws {
        guard frames.count == delays.count else {
            throw TestMediaError.frameDelayCountMismatch
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw TestMediaError.unableToCreateDestination
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0,
                ],
            ] as CFDictionary
        )

        for (image, delay) in zip(frames, delays) {
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                    kCGImagePropertyGIFDelayTime: delay,
                ],
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw TestMediaError.unableToFinalizeGIF
        }
    }

    private static func makeSolidImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw TestMediaError.unableToCreateImage
        }

        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestMediaError.unableToCreateImage
        }
        return image
    }

    private static func writeTransparentGIF(
        at url: URL,
        includesGlobalColorTable: Bool
    ) throws {
        let width = 32
        let height = 24
        var data = Data("GIF89a".utf8)
        data.appendLittleEndian(UInt16(width))
        data.appendLittleEndian(UInt16(height))
        data.append(includesGlobalColorTable ? 0x80 : 0x00)
        data.append(0)
        data.append(0)

        let palette: [UInt8] = [
            includesGlobalColorTable ? 0 : 255,
            includesGlobalColorTable ? 255 : 0,
            0,
            255, 0, 0,
        ]
        if includesGlobalColorTable {
            data.append(contentsOf: palette)
        }

        data.append(contentsOf: [
            0x21, 0xF9, 0x04,
            0x01,
            0x0A, 0x00,
            0x00,
            0x00,
            0x2C,
        ])
        data.appendLittleEndian(0)
        data.appendLittleEndian(0)
        data.appendLittleEndian(UInt16(width))
        data.appendLittleEndian(UInt16(height))
        data.append(includesGlobalColorTable ? 0x00 : 0x80)
        if !includesGlobalColorTable {
            data.append(contentsOf: palette)
        }

        let pixels = (0..<height).flatMap { _ in
            (0..<width).map { $0 < width / 2 ? UInt8(0) : UInt8(1) }
        }
        let compressed = clearSeparatedLZWData(for: pixels)
        data.append(2)
        var offset = 0
        while offset < compressed.count {
            let count = min(255, compressed.count - offset)
            data.append(UInt8(count))
            data.append(contentsOf: compressed[offset..<(offset + count)])
            offset += count
        }
        data.append(0)
        data.append(0x3B)
        try data.write(to: url)
    }

    private static func clearSeparatedLZWData(for pixels: [UInt8]) -> [UInt8] {
        let clearCode = 4
        let endCode = 5
        var codes = pixels.flatMap { [clearCode, Int($0)] }
        codes.append(endCode)

        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        var bitIndex = 0
        for code in codes {
            for codeBit in 0..<3 {
                if code & (1 << codeBit) != 0 {
                    byte |= 1 << bitIndex
                }
                bitIndex += 1
                if bitIndex == 8 {
                    bytes.append(byte)
                    byte = 0
                    bitIndex = 0
                }
            }
        }
        if bitIndex > 0 {
            bytes.append(byte)
        }
        return bytes
    }
}

private enum TestMediaError: Error {
    case unableToCreateDestination
    case unableToFinalizeGIF
    case unableToCreateImage
    case frameDelayCountMismatch
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}
