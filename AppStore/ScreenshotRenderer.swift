import AppKit
import Foundation

@main
struct ColdHotScreenshotRenderer {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)

        let suiteName = "com.xipiyoung.ColdHot.ScreenshotRenderer"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = MonitorSettings(defaults: defaults)
        for metric in BuildVariant.availableMetrics {
            settings.setEnabled(true, for: metric)
        }

        let monitor = PerformanceMonitor(settings: settings)
        let dockController = DockDelayController()
        let panelBackgroundStore = PanelBackgroundStore()
        let updateController = UpdateController()

        // CPU utilization requires two samples. Keep the main run loop moving
        // so the real sampler can publish its first complete snapshot.
        RunLoop.current.run(until: Date().addingTimeInterval(2.4))

        for shot in ScreenshotKind.allCases {
            monitor.setExpandedMetric(shot.expandedMetric)
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))

            ScreenshotCanvas(
                shot: shot,
                monitor: monitor,
                settings: settings,
                dockController: dockController,
                panelBackgroundStore: panelBackgroundStore,
                updateController: updateController
            )
            .renderPNG()
        }
    }
}
