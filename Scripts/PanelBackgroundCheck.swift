import Foundation
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
enum PanelBackgroundCheck {
    @MainActor
    static func main() throws {
        checkSettingsPersistence()
        try checkImageLifecycle()
        checkBackgroundRendering()
        checkReadabilityRendering()
        print("Panel background checks passed")
    }

    private static func checkSettingsPersistence() {
        let suiteName = "com.xipiyoung.ColdHot.panel-background-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = MonitorSettings(defaults: defaults)
        expect(!initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundDimOpacity == 0.35)
        expect(initial.panelCardOpacity == 1)
        expect(initial.panelTextOpacity == 1)

        initial.setPanelBackgroundEnabled(true)
        initial.setPanelBackgroundDimOpacity(1)
        initial.setPanelCardOpacity(2)
        initial.setPanelTextOpacity(2)

        let restored = MonitorSettings(defaults: defaults)
        expect(restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.70)
        expect(restored.panelCardOpacity == 1)
        expect(restored.panelTextOpacity == 1)

        restored.setPanelBackgroundDimOpacity(-1)
        restored.setPanelCardOpacity(0)
        restored.setPanelTextOpacity(0)
        expect(restored.panelBackgroundDimOpacity == 0)
        expect(restored.panelCardOpacity == 0.10)
        expect(restored.panelTextOpacity == 0.50)

        restored.reset()
        expect(!restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.35)
        expect(restored.panelCardOpacity == 1)
        expect(restored.panelTextOpacity == 1)
    }

    @MainActor
    private static func checkImageLifecycle() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ColdHotPanelBackgroundCheck-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let sourceURL = rootDirectory.appendingPathComponent("source.png")
        try writeTestPNG(
            to: sourceURL,
            width: 2_400,
            height: 1_200,
            color: .systemRed
        )

        let storeDirectory = rootDirectory.appendingPathComponent("store")
        let store = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(!store.hasImage)

        try store.importImage(from: sourceURL)
        expect(store.hasImage)
        expect(store.fileURL.lastPathComponent == "background.png")
        let storedPixelSize = try pixelSize(of: store.fileURL)
        expect(storedPixelSize == CGSize(width: 1_600, height: 800))

        let smallSourceURL = rootDirectory.appendingPathComponent("small-source.png")
        try writeTestPNG(
            to: smallSourceURL,
            width: 320,
            height: 200,
            color: .systemBlue
        )
        try store.importImage(from: smallSourceURL)
        let smallStoredPixelSize = try pixelSize(of: store.fileURL)
        expect(smallStoredPixelSize == CGSize(width: 320, height: 200))

        let storedBeforeInvalidImport = try Data(contentsOf: store.fileURL)
        let invalidURL = rootDirectory.appendingPathComponent("invalid.txt")
        try Data("not an image".utf8).write(to: invalidURL)
        do {
            try store.importImage(from: invalidURL)
            fatalError("Invalid image import should fail")
        } catch {}
        expect(store.hasImage)
        let storedAfterInvalidImport = try Data(contentsOf: store.fileURL)
        expect(storedAfterInvalidImport == storedBeforeInvalidImport)

        let restored = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(restored.hasImage)
        expect(restored.image != nil)

        try fileManager.removeItem(at: restored.fileURL)
        expect(restored.hasImage)
        let missingFileStore = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(!missingFileStore.hasImage)

        try restored.removeImage()
        expect(!restored.hasImage)
        expect(!fileManager.fileExists(atPath: restored.fileURL.path))
    }

    private static func writeTestPNG(
        to url: URL,
        width: Int,
        height: Int,
        color: NSColor
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Unable to create test image context")
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            fatalError("Unable to create test PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Unable to write test PNG")
        }
    }

    private static func pixelSize(of url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            fatalError("Unable to inspect image dimensions")
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    @MainActor
    private static func checkBackgroundRendering() {
        let image = solidImage(width: 100, height: 100, color: .systemRed)
        let clearPixel = renderCenterPixel(image: image, dimOpacity: 0)
        let dimmedPixel = renderCenterPixel(image: image, dimOpacity: 0.35)

        expect(clearPixel.redComponent > 0.9)
        expect(clearPixel.redComponent > clearPixel.greenComponent)
        expect(dimmedPixel.redComponent < clearPixel.redComponent * 0.8)
        expect(dimmedPixel.redComponent > dimmedPixel.greenComponent)
    }

    @MainActor
    private static func checkReadabilityRendering() {
        let opaqueCard = renderCardCenterPixel(
            cardOpacity: 1,
            usesCustomBackground: true
        )
        let translucentCard = renderCardCenterPixel(
            cardOpacity: 0.10,
            usesCustomBackground: true
        )
        let nativeCard = renderCardCenterPixel(
            cardOpacity: 0.10,
            usesCustomBackground: false
        )

        expect(translucentCard.redComponent > opaqueCard.redComponent)
        expect(abs(nativeCard.redComponent - opaqueCard.redComponent) < 0.05)

        let fullText = renderTextCenterPixel(
            textOpacity: 1,
            usesCustomBackground: true
        )
        let dimmedText = renderTextCenterPixel(
            textOpacity: 0.50,
            usesCustomBackground: true
        )
        let nativeText = renderTextCenterPixel(
            textOpacity: 0.50,
            usesCustomBackground: false
        )

        expect(brightness(of: fullText) > 0.90)
        expect(brightness(of: dimmedText) < brightness(of: fullText) * 0.75)
        expect(brightness(of: nativeText) > 0.90)
    }

    @MainActor
    private static func renderCardCenterPixel(
        cardOpacity: Double,
        usesCustomBackground: Bool
    ) -> NSColor {
        let content = ZStack {
            Color.red
            PanelCardBackground(cornerRadius: 0)
        }
        .panelReadability(
            cardOpacity: cardOpacity,
            textOpacity: 1,
            usesCustomBackground: usesCustomBackground
        )
        return renderCenterPixel(content)
    }

    @MainActor
    private static func renderTextCenterPixel(
        textOpacity: Double,
        usesCustomBackground: Bool
    ) -> NSColor {
        let content = ZStack {
            Color.black
            Color.white
                .frame(width: 60, height: 60)
                .panelTextReadability()
        }
        .panelReadability(
            cardOpacity: 1,
            textOpacity: textOpacity,
            usesCustomBackground: usesCustomBackground
        )
        return renderCenterPixel(content)
    }

    @MainActor
    private static func renderCenterPixel<Content: View>(
        _ content: Content
    ) -> NSColor {
        let side: CGFloat = 100
        let hostingView = NSHostingView(
            rootView: content.frame(width: side, height: side)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create readability render bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let color = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.usingColorSpace(.deviceRGB) else {
            fatalError("Unable to sample readability render")
        }
        return color
    }

    @MainActor
    private static func renderCenterPixel(
        image: NSImage,
        dimOpacity: Double
    ) -> NSColor {
        let side: CGFloat = 100
        let content = PanelBackgroundView(
            image: image,
            isEnabled: true,
            dimOpacity: dimOpacity
        )
        .frame(width: side, height: side)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create background render bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let color = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.usingColorSpace(.deviceRGB) else {
            fatalError("Unable to sample background render")
        }
        return color
    }

    private static func solidImage(
        width: Int,
        height: Int,
        color: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Unable to create solid image context")
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("Unable to create solid image")
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: width, height: height)
        )
    }

    private static func brightness(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            fatalError("Unable to convert sampled color to sRGB")
        }
        return max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
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
