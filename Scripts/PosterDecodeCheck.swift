import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum PosterDecodeCheck {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ColdHotPosterDecodeCheck-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("background.png")
        try writePNG(to: legacyURL, width: 1_320, height: 660)
        let store = PanelBackgroundStore(directoryURL: directory)
        guard let size = store.image?.size else {
            fatalError("Legacy background should decode")
        }
        expect(max(size.width, size.height) <= 960)
        expect(abs(size.width / size.height - 2) < 0.001)
        print("Poster decode checks passed: \(Int(size.width))x\(Int(size.height))")
    }

    private static func writePNG(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
           ) else {
            fatalError("Unable to create fixture image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Unable to write fixture image")
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Check failed", file: file, line: line)
        }
    }
}
