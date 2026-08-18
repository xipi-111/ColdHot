import SwiftUI
import AppKit

@main
struct ColdHotApp: App {
    @StateObject private var settings: MonitorSettings
    @StateObject private var monitor: PerformanceMonitor
    @StateObject private var dockController: DockDelayController
    @StateObject private var panelBackgroundStore: PanelBackgroundStore

    init() {
        let settings = MonitorSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: PerformanceMonitor(settings: settings))
        _dockController = StateObject(wrappedValue: DockDelayController())
        _panelBackgroundStore = StateObject(wrappedValue: PanelBackgroundStore())
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                monitor: monitor,
                settings: settings,
                dockController: dockController,
                panelBackgroundStore: panelBackgroundStore
            )
        } label: {
            MenuBarStatusLabel(monitor: monitor, fallbackSymbol: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: settings,
                panelBackgroundStore: panelBackgroundStore
            )
        }
    }

    private var menuBarSymbol: String {
        switch monitor.snapshot.thermal.state {
        case .nominal: "gauge.with.dots.needle.33percent"
        case .fair: "gauge.with.dots.needle.50percent"
        case .serious, .critical: "gauge.with.dots.needle.67percent"
        @unknown default: "gauge.with.dots.needle.50percent"
        }
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var monitor: PerformanceMonitor
    let fallbackSymbol: String

    var body: some View {
        if let alert = monitor.visibleThresholdAlert {
            Image(nsImage: Self.statusImage(for: alert))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(alert.measurement.objectLabel) \(alert.measurement.valueText)"
            )
        } else {
            Image(systemName: fallbackSymbol)
                .accessibilityLabel("ColdHot 性能监控")
        }
    }

    private static func statusImage(for alert: ThresholdAlert) -> NSImage {
        let valueText = alert.measurement.valueText
        let hasDegreeMark = valueText.hasSuffix("°")
        let value = (hasDegreeMark ? String(valueText.dropLast()) : valueText) as NSString
        let degreeMark = hasDegreeMark ? "°" as NSString : nil
        let object = alert.measurement.objectLabel as NSString
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let degreeFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
        let objectFont = NSFont.systemFont(ofSize: 7, weight: .medium)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]
        let objectAttributes: [NSAttributedString.Key: Any] = [
            .font: objectFont,
            .foregroundColor: NSColor.black
        ]
        let degreeAttributes: [NSAttributedString.Key: Any] = [
            .font: degreeFont,
            .foregroundColor: NSColor.black
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
        image.isTemplate = true
        return image
    }
}
