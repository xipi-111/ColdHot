import AppKit
import QuartzCore

@main
enum FanSpinnerCenterCheck {
    static func main() throws {
        let side: CGFloat = 12
        let backingScale: CGFloat = 8
        let canvasSize = CGSize(width: side, height: side)
        let pointConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .regular
        )
        guard let symbol = NSImage(
            systemSymbolName: "fan.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(pointConfiguration) else {
            fatalError("Unable to load fan.fill")
        }

        let fittedRect = FanSpinnerGeometry.fittedSymbolRect(
            imageSize: symbol.size,
            alignmentRect: symbol.alignmentRect,
            canvasSize: canvasSize
        )
        let mappedCenter = FanSpinnerGeometry.mappedSymbolCenter(
            alignmentRect: symbol.alignmentRect,
            fittedRect: fittedRect,
            imageSize: symbol.size
        )
        let expectedCenter = CGPoint(x: side / 2, y: side / 2)
        expect(distance(mappedCenter, expectedCenter) < 0.0001)

        let containerLayer = CALayer()
        containerLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        let fanLayer = CALayer()
        fanLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        fanLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fanLayer.position = expectedCenter
        containerLayer.addSublayer(fanLayer)

        let angles = stride(from: 0.0, to: 360.0, by: 45.0).map { $0 }
        var maximumDrift: CGFloat = 0
        for angle in angles {
            fanLayer.setAffineTransform(
                CGAffineTransform(rotationAngle: CGFloat(angle * .pi / 180))
            )
            let centerAfterRotation = fanLayer.convert(expectedCenter, to: containerLayer)
            maximumDrift = max(maximumDrift, distance(centerAfterRotation, expectedCenter))
        }
        expect(maximumDrift < 0.0001)

        checkLiveSpinnerLayer(expectedCenter: expectedCenter, side: side)

        let outputPath = CommandLine.arguments.dropFirst().first
            ?? "/tmp/coldhot-fan-center-check.png"
        try renderRotationStrip(
            angles: angles,
            side: side,
            backingScale: backingScale,
            outputPath: outputPath
        )
        print(
            "Fan center checks passed; maximum rotation-center drift "
                + String(format: "%.4f pt", maximumDrift)
        )
        print(outputPath)
    }

    private static func checkLiveSpinnerLayer(
        expectedCenter: CGPoint,
        side: CGFloat
    ) {
        let spinner = FanSpinnerView(
            frame: CGRect(x: 0, y: 0, width: side, height: side)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: side, height: side),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = spinner
        spinner.layoutSubtreeIfNeeded()
        spinner.setSpeed(2_000)

        let layer = Mirror(reflecting: spinner).children.first {
            $0.label == "fanLayer"
        }?.value as? CALayer
        guard let layer else { fatalError("Unable to inspect live fan layer") }
        expect(distance(layer.position, expectedCenter) < 0.0001)
        expect(layer.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        expect(layer.bounds.size == CGSize(width: side, height: side))
        expect(layer.animation(forKey: "coldhot.fan.rotation") != nil)

        spinner.setSpeed(0)
        expect(layer.animation(forKey: "coldhot.fan.rotation") == nil)
    }

    private static func renderRotationStrip(
        angles: [Double],
        side: CGFloat,
        backingScale: CGFloat,
        outputPath: String
    ) throws {
        guard let fanImage = FanSymbolRenderer.makeImage(
            side: side,
            backingScale: backingScale,
            color: .white
        ) else {
            fatalError("Unable to render fan.fill")
        }

        let cellSide = fanImage.width
        let gap = 8
        let width = cellSide * angles.count + gap * (angles.count - 1)
        let height = cellSide
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
            fatalError("Unable to create preview context")
        }

        for (index, angle) in angles.enumerated() {
            let originX = index * (cellSide + gap)
            let center = CGPoint(
                x: CGFloat(originX) + CGFloat(cellSide) / 2,
                y: CGFloat(cellSide) / 2
            )
            context.setFillColor(NSColor.darkGray.cgColor)
            context.fill(
                CGRect(x: originX, y: 0, width: cellSide, height: cellSide)
            )

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(angle * .pi / 180))
            context.translateBy(
                x: -CGFloat(cellSide) / 2,
                y: -CGFloat(cellSide) / 2
            )
            context.interpolationQuality = .high
            context.draw(
                fanImage,
                in: CGRect(x: 0, y: 0, width: cellSide, height: cellSide)
            )
            context.restoreGState()

            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(
                in: CGRect(
                    x: center.x - 2,
                    y: center.y - 2,
                    width: 4,
                    height: 4
                )
            )
        }

        guard let preview = context.makeImage() else {
            fatalError("Unable to create preview image")
        }
        let bitmap = NSBitmapImageRep(cgImage: preview)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode preview image")
        }
        try png.write(to: URL(fileURLWithPath: outputPath))
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
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
