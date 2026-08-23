import SwiftUI
import AppKit
#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@main
struct ColdHotApp: App {
    @StateObject private var settings: MonitorSettings
    @StateObject private var monitor: PerformanceMonitor
    @StateObject private var dockController: DockDelayController
    @StateObject private var panelBackgroundStore: PanelBackgroundStore
    @StateObject private var panelBackgroundPlaybackController: PanelBackgroundPlaybackController
    @StateObject private var updateController: UpdateController

    init() {
        let settings = MonitorSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: PerformanceMonitor(settings: settings))
        _dockController = StateObject(wrappedValue: DockDelayController())
        _panelBackgroundStore = StateObject(wrappedValue: PanelBackgroundStore())
        _panelBackgroundPlaybackController = StateObject(
            wrappedValue: PanelBackgroundPlaybackController()
        )
        _updateController = StateObject(wrappedValue: UpdateController())
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                monitor: monitor,
                settings: settings,
                dockController: dockController,
                panelBackgroundStore: panelBackgroundStore,
                panelBackgroundPlaybackController: panelBackgroundPlaybackController,
                updateController: updateController
            )
        } label: {
            MenuBarStatusLabel(monitor: monitor, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: settings,
                panelBackgroundStore: panelBackgroundStore,
                monitor: monitor,
                updateController: updateController
            )
        }
    }

}

#if DIRECT_DISTRIBUTION
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        _ = updaterController
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set {
            updaterController.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableVersion = nil
    }
}
#else
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableVersion: String?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    init() {}
    func checkForUpdates() {}
}
#endif

private struct MenuBarStatusLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var performance: MenuBarPerformanceProjection
    @ObservedObject var settings: MonitorSettings

    init(monitor: PerformanceMonitor, settings: MonitorSettings) {
        _performance = ObservedObject(wrappedValue: monitor.menuBarProjection)
        self.settings = settings
    }

    var body: some View {
        if let alert = performance.visibleThresholdAlert {
            Image(
                nsImage: MenuBarStatusRenderer.alertImage(
                    measurement: alert.measurement,
                    severity: alert.severity,
                    colors: settings.thresholdSeverityColors,
                    appearance: NSAppearance(
                        named: colorScheme == .dark ? .darkAqua : .aqua
                    )
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MenuBarStatusRenderer.accessibilityLabel(for: alert))
        } else {
            Image(nsImage: MenuBarStatusRenderer.pulseImage())
                .accessibilityLabel("ColdHot 性能监控")
        }
    }
}
