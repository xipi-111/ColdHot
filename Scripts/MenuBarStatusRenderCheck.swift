import AppKit
import Foundation

@main
enum MenuBarStatusRenderCheck {
    static func main() throws {
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? ".build/status-severity/renders",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let idle = MenuBarStatusRenderer.pulseImage()
        expect(idle.size == NSSize(width: 18, height: 18))
        expect(idle.isTemplate)
        let pulsePath = MenuBarStatusRenderer.pulsePath()
        expect(!containsClosedContour(pulsePath))
        expect(moveElementCount(in: pulsePath) == 1)
        let forbiddenRing = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
        expect(containsClosedContour(forbiddenRing))
        let idleBitmap = bitmap(for: idle, scale: 4, background: .clear)
        let idleBounds = inkBounds(in: idleBitmap)
        expect(idleBounds.minX <= 5)
        expect(idleBounds.maxX >= idleBitmap.pixelsWide - 6)
        expect(idleBounds.minY <= 8)
        expect(idleBounds.maxY >= idleBitmap.pixelsHigh - 9)
        expect(alpha(atX: 4, y: 4, in: idleBitmap) == 0)
        expect(alpha(atX: idleBitmap.pixelsWide - 5, y: 4, in: idleBitmap) == 0)
        try write(idleBitmap, named: "pulse-template.png", to: outputDirectory)

        let colors = ThresholdSeverityColors.recommended
        let compact = ThresholdMeasurement(rawValue: 94, valueText: "94°", objectLabel: "CPU")
        let accessibilityAlert = ThresholdAlert(
            kind: .temperatureCPU,
            measurement: compact,
            thresholdValue: 90,
            severity: .level3,
            activatedAt: Date(timeIntervalSince1970: 1)
        )
        expect(
            MenuBarStatusRenderer.accessibilityLabel(for: accessibilityAlert)
                == "CPU 94° 三级"
        )
        let crowded = ThresholdMeasurement(
            rawValue: 12_345,
            valueText: "12345W",
            objectLabel: "电源管理"
        )
        var inkCounts: [ThresholdSeverity: Int] = [:]

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: appearanceName)!
            let appearanceSlug = appearanceName == .darkAqua ? "dark" : "light"
            for severity in ThresholdSeverity.allCases {
                let image = MenuBarStatusRenderer.alertImage(
                    measurement: compact,
                    severity: severity,
                    colors: colors,
                    appearance: appearance
                )
                expect(image.size.height == 20)
                expect(image.size.width >= 24 && image.size.width <= 54)
                expect(!image.isTemplate)
                let bitmap = bitmap(for: image, scale: 4, background: .clear)
                inkCounts[severity] = max(inkCounts[severity] ?? 0, opaquePixelCount(in: bitmap))
                try write(
                    bitmap,
                    named: "alert-\(severity.rawValue)-\(appearanceSlug).png",
                    to: outputDirectory
                )

                let sampled = brightestInkColor(in: bitmap)
                switch severity {
                case .level1:
                    if appearanceName == .darkAqua {
                        expect(
                            sampled.redComponent > 0.75
                                && sampled.greenComponent > 0.75
                                && sampled.blueComponent > 0.75
                        )
                    } else {
                        expect(
                            sampled.redComponent < 0.35
                                && sampled.greenComponent < 0.35
                                && sampled.blueComponent < 0.35
                        )
                    }
                case .level2:
                    expect(
                        sampled.redComponent > 0.75
                            && sampled.greenComponent > 0.55
                            && sampled.blueComponent < 0.35
                    )
                case .level3:
                    expect(
                        sampled.redComponent > 0.75
                            && sampled.greenComponent < 0.45
                            && sampled.blueComponent < 0.45
                    )
                }
            }

            let crowdedImage = MenuBarStatusRenderer.alertImage(
                measurement: crowded,
                severity: .level3,
                colors: colors,
                appearance: appearance
            )
            expect(crowdedImage.size.width <= 72)
            try write(
                bitmap(for: crowdedImage, scale: 4, background: .clear),
                named: "alert-crowded-\(appearanceSlug).png",
                to: outputDirectory
            )
        }

        expect((inkCounts[.level3] ?? 0) > (inkCounts[.level1] ?? 0))
        print("Menu bar status render checks passed")
    }

    private static func bitmap(
        for image: NSImage,
        scale: Int,
        background: NSColor
    ) -> NSBitmapImageRep {
        let width = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        background.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func inkBounds(in bitmap: NSBitmapImageRep) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        var minX = bitmap.pixelsWide
        var maxX = 0
        var minY = bitmap.pixelsHigh
        var maxY = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where alpha(atX: x, y: y, in: bitmap) > 12 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return (minX, maxX, minY, maxY)
    }

    private static func alpha(atX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> Int {
        Int((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255)
    }

    private static func opaquePixelCount(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where alpha(atX: x, y: y, in: bitmap) > 50 {
                count += 1
            }
        }
        return count
    }

    private static func brightestInkColor(in bitmap: NSBitmapImageRep) -> NSColor {
        var selected = NSColor.clear
        var selectedBrightness = -1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.8,
                      let rgb = color.usingColorSpace(.sRGB) else { continue }
                let brightness = rgb.redComponent + rgb.greenComponent + rgb.blueComponent
                if brightness > selectedBrightness {
                    selected = rgb
                    selectedBrightness = brightness
                }
            }
        }
        return selected
    }

    private static func write(
        _ bitmap: NSBitmapImageRep,
        named name: String,
        to directory: URL
    ) throws {
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static func containsClosedContour(_ path: NSBezierPath) -> Bool {
        if (0..<path.elementCount).contains(where: { index in
            path.element(at: index) == .closePath
        }) {
            return true
        }
        guard path.elementCount > 0 else { return false }
        var points = [NSPoint](repeating: .zero, count: 3)
        guard path.element(at: 0, associatedPoints: &points) == .moveTo else {
            return false
        }
        let start = points[0]
        let end = path.currentPoint
        return hypot(end.x - start.x, end.y - start.y) < 0.01
    }

    private static func moveElementCount(in path: NSBezierPath) -> Int {
        (0..<path.elementCount).filter { index in
            path.element(at: index) == .moveTo
        }.count
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else { fatalError("Check failed", file: file, line: line) }
    }
}
