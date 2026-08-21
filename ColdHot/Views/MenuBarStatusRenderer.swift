import AppKit

enum MenuBarStatusRenderer {
    static func pulseImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = pulsePath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func pulsePath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 1.25, y: 9))
        path.line(to: NSPoint(x: 4.6, y: 9))
        path.line(to: NSPoint(x: 6.1, y: 12.1))
        path.line(to: NSPoint(x: 7.6, y: 6.8))
        path.line(to: NSPoint(x: 9.2, y: 16.1))
        path.line(to: NSPoint(x: 11, y: 1.9))
        path.line(to: NSPoint(x: 12.8, y: 10.7))
        path.line(to: NSPoint(x: 14.3, y: 8.5))
        path.line(to: NSPoint(x: 16.75, y: 8.5))
        return path
    }

    static func alertImage(
        measurement: ThresholdMeasurement,
        severity: ThresholdSeverity,
        colors: ThresholdSeverityColors,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let render = {
            makeAlertImage(
                measurement: measurement,
                severity: severity,
                color: resolvedColor(for: severity, colors: colors)
            )
        }
        if let appearance {
            var image: NSImage?
            appearance.performAsCurrentDrawingAppearance {
                image = render()
            }
            return image!
        }
        return render()
    }

    static func colorComponents(from color: NSColor) -> ThresholdColorComponents {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return ThresholdColorComponents(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: rgb.alphaComponent
        )
    }

    static func accessibilityLabel(for alert: ThresholdAlert) -> String {
        "\(alert.measurement.objectLabel) \(alert.measurement.valueText) \(alert.severity.title)"
    }

    private static func makeAlertImage(
        measurement: ThresholdMeasurement,
        severity: ThresholdSeverity,
        color: NSColor
    ) -> NSImage {
        let valueText = measurement.valueText
        let hasDegreeMark = valueText.hasSuffix("°")
        let value = (hasDegreeMark ? String(valueText.dropLast()) : valueText) as NSString
        let degreeMark = hasDegreeMark ? "°" as NSString : nil
        let object = measurement.objectLabel as NSString
        let weight = fontWeight(for: severity)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight)
        let degreeFont = NSFont.systemFont(ofSize: 7, weight: weight)
        let objectFont = NSFont.systemFont(ofSize: 7, weight: weight)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: color
        ]
        let objectAttributes: [NSAttributedString.Key: Any] = [
            .font: objectFont,
            .foregroundColor: color
        ]
        let degreeAttributes: [NSAttributedString.Key: Any] = [
            .font: degreeFont,
            .foregroundColor: color
        ]
        let valueSize = value.size(withAttributes: valueAttributes)
        let objectSize = object.size(withAttributes: objectAttributes)
        let degreeSize = degreeMark?.size(withAttributes: degreeAttributes) ?? .zero
        let centeredValueWidth = valueSize.width + degreeSize.width * 2
        let width = max(24, ceil(max(centeredValueWidth, objectSize.width)) + 4)
        let size = NSSize(width: width, height: 20)
        let valueX = floor((width - valueSize.width) / 2)
        let objectX = floor((width - objectSize.width) / 2)

        let image = NSImage(size: size, flipped: true) { _ in
            value.draw(at: NSPoint(x: valueX, y: -3), withAttributes: valueAttributes)
            degreeMark?.draw(
                at: NSPoint(x: valueX + valueSize.width - 0.5, y: -1),
                withAttributes: degreeAttributes
            )
            object.draw(at: NSPoint(x: objectX, y: 11), withAttributes: objectAttributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func fontWeight(for severity: ThresholdSeverity) -> NSFont.Weight {
        switch severity {
        case .level1: .semibold
        case .level2: .bold
        case .level3: .heavy
        }
    }

    private static func resolvedColor(
        for severity: ThresholdSeverity,
        colors: ThresholdSeverityColors
    ) -> NSColor {
        let components: ThresholdColorComponents?
        switch severity {
        case .level1: components = colors.level1Custom
        case .level2: components = colors.level2
        case .level3: components = colors.level3
        }
        guard let components else {
            return NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return NSColor(
            srgbRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }
}
