import SwiftUI

@main
struct ColdHotApp: App {
    @StateObject private var settings: MonitorSettings
    @StateObject private var monitor: PerformanceMonitor
    @StateObject private var dockController: DockDelayController

    init() {
        let settings = MonitorSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: PerformanceMonitor(settings: settings))
        _dockController = StateObject(wrappedValue: DockDelayController())
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                monitor: monitor,
                settings: settings,
                dockController: dockController
            )
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel("ColdHot 性能监控")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
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
