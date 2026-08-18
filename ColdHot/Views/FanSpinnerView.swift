import SwiftUI
import AppKit
import QuartzCore

struct SpinningFanIcon: NSViewRepresentable {
    let rpm: Double

    func makeNSView(context: Context) -> FanSpinnerView {
        FanSpinnerView()
    }

    func updateNSView(_ view: FanSpinnerView, context: Context) {
        view.setSpeed(rpm)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FanSpinnerView,
        context: Context
    ) -> CGSize? {
        CGSize(width: 12, height: 12)
    }
}

enum FanSpinnerGeometry {
    static func fittedSymbolRect(
        imageSize: CGSize,
        alignmentRect: CGRect,
        canvasSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let scale = min(
            canvasSize.width / imageSize.width,
            canvasSize.height / imageSize.height
        )
        let symbolCenter = CGPoint(
            x: alignmentRect.midX,
            y: alignmentRect.midY
        )
        let canvasCenter = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )

        return CGRect(
            x: canvasCenter.x - symbolCenter.x * scale,
            y: canvasCenter.y - symbolCenter.y * scale,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    static func mappedSymbolCenter(
        alignmentRect: CGRect,
        fittedRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(
            x: fittedRect.minX + alignmentRect.midX * fittedRect.width / imageSize.width,
            y: fittedRect.minY + alignmentRect.midY * fittedRect.height / imageSize.height
        )
    }
}

enum FanSymbolRenderer {
    static func makeImage(
        side: CGFloat,
        backingScale: CGFloat,
        pointSize: CGFloat = 11,
        color: NSColor
    ) -> CGImage? {
        guard side > 0, backingScale > 0 else { return nil }

        let pixelSide = max(1, Int(ceil(side * backingScale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelSide,
            height: pixelSide,
            bitsPerComponent: 8,
            bytesPerRow: pixelSide * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.scaleBy(x: backingScale, y: backingScale)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let pointConfiguration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )
        let colorConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: color)
        guard let symbol = NSImage(
            systemSymbolName: "fan.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(pointConfiguration.applying(colorConfiguration)) else {
            return nil
        }

        let canvasSize = CGSize(width: side, height: side)
        let symbolRect = FanSpinnerGeometry.fittedSymbolRect(
            imageSize: symbol.size,
            alignmentRect: symbol.alignmentRect,
            canvasSize: canvasSize
        )
        symbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        return context.makeImage()
    }
}

final class FanSpinnerView: NSView {
    private static let animationKey = "coldhot.fan.rotation"

    private let fanLayer = CALayer()
    private var shouldSpin = false
    private var renderedSide: CGFloat = 0
    private var renderedScale: CGFloat = 0
    private var renderedAppearanceName: NSAppearance.Name?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fanLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fanLayer.contentsGravity = .resize
        fanLayer.masksToBounds = false
        fanLayer.allowsEdgeAntialiasing = true
        layer?.addSublayer(fanLayer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fanLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        fanLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        updateContentsIfNeeded()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsIfNeeded(force: true)
        updateAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContentsIfNeeded(force: true)
    }

    func setSpeed(_ rpm: Double) {
        let newValue = rpm > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard newValue != shouldSpin else { return }
        shouldSpin = newValue
        updateAnimation()
    }

    private func updateContentsIfNeeded(force: Bool = false) {
        let side = fanLayer.bounds.width
        guard side > 0 else { return }

        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let appearanceName = effectiveAppearance.name
        guard force
                || abs(side - renderedSide) > 0.001
                || abs(scale - renderedScale) > 0.001
                || appearanceName != renderedAppearanceName else {
            return
        }

        var image: CGImage?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            image = FanSymbolRenderer.makeImage(
                side: side,
                backingScale: scale,
                color: .secondaryLabelColor
            )
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.contents = image
        fanLayer.contentsScale = scale
        CATransaction.commit()

        renderedSide = side
        renderedScale = scale
        renderedAppearanceName = appearanceName
    }

    private func updateAnimation() {
        let isAnimating = fanLayer.animation(forKey: Self.animationKey) != nil
        let hasFinalLayout = window != nil
            && fanLayer.bounds.width > 0
            && fanLayer.bounds.height > 0

        guard shouldSpin && hasFinalLayout else {
            if isAnimating {
                fanLayer.removeAnimation(forKey: Self.animationKey)
            }
            return
        }
        guard !isAnimating else { return }

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 1.35
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        fanLayer.add(animation, forKey: Self.animationKey)
    }
}
