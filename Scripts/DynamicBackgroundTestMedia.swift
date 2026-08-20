import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DynamicBackgroundTestMedia {
    static func makeTwoFrameGIF(at url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
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

        let frames: [(red: CGFloat, green: CGFloat, blue: CGFloat, delay: Double)] = [
            (1, 0, 0, 0.10),
            (0, 0, 1, 0.25),
        ]

        for frame in frames {
            let image = try makeSolidImage(red: frame.red, green: frame.green, blue: frame.blue)
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
                    kCGImagePropertyGIFDelayTime: frame.delay,
                ],
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw TestMediaError.unableToFinalizeGIF
        }
    }

    private static func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: 32,
                height: 24,
                bitsPerComponent: 8,
                bytesPerRow: 32 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw TestMediaError.unableToCreateImage
        }

        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))

        guard let image = context.makeImage() else {
            throw TestMediaError.unableToCreateImage
        }
        return image
    }
}

private enum TestMediaError: Error {
    case unableToCreateDestination
    case unableToFinalizeGIF
    case unableToCreateImage
}
