import Combine
import Foundation

@main
enum PerformancePublishingCheck {
    static func main() {
        checkPanelProjectionVisibility()
        checkMenuProjectionDeduplicatesEqualAlerts()
        checkSettingsProjectionVisibility()
        checkExpandedMetricRefreshDeduplication()
        print("Performance publishing checks passed")
    }

    private static func checkPanelProjectionVisibility() {
        let projection = PanelPerformanceProjection()
        var publications = 0
        let subscription = projection.objectWillChange.sink { publications += 1 }
        var latest = PerformancePresentationState.empty
        latest.snapshot.timestamp = Date(timeIntervalSince1970: 123)

        projection.publish(latest)
        expect(publications == 0)
        projection.setVisible(true, latest: latest)
        expect(publications == 1)
        expect(projection.snapshot.timestamp == latest.snapshot.timestamp)
        projection.publish(latest)
        expect(publications == 2)
        projection.setVisible(false, latest: latest)
        projection.publish(latest)
        expect(publications == 2)
        withExtendedLifetime(subscription) {}
    }

    private static func checkMenuProjectionDeduplicatesEqualAlerts() {
        let projection = MenuBarPerformanceProjection()
        var publications = 0
        let subscription = projection.objectWillChange.sink { publications += 1 }
        let alert = ThresholdAlert(
            kind: .cpuUsage,
            measurement: ThresholdMeasurement(
                rawValue: 88,
                valueText: "88%",
                objectLabel: "CPU"
            ),
            thresholdValue: 80,
            severity: .level1,
            activatedAt: Date(timeIntervalSince1970: 123)
        )

        projection.publish(alert)
        expect(publications == 1)
        projection.publish(alert)
        expect(publications == 1)
        projection.publish(nil)
        expect(publications == 2)
        withExtendedLifetime(subscription) {}
    }

    private static func checkSettingsProjectionVisibility() {
        let projection = SettingsPerformanceProjection()
        var publications = 0
        let subscription = projection.objectWillChange.sink { publications += 1 }
        var state = SettingsPerformanceState.empty
        state.selfResource.memoryBytes = 42

        projection.publish(state)
        expect(publications == 0)
        projection.setActive(true, latest: state)
        expect(publications == 1)
        expect(projection.selfResourceSnapshot.memoryBytes == 42)
        projection.publish(state)
        expect(publications == 2)
        projection.setActive(false, latest: state)
        projection.publish(state)
        expect(publications == 2)
        withExtendedLifetime(subscription) {}
    }

    private static func checkExpandedMetricRefreshDeduplication() {
        let suite = "com.xipiyoung.ColdHot.performance-publishing-check"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Unable to create defaults")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        var sampleCount = 0
        let monitor = PerformanceMonitor(
            settings: settings,
            startsAutomatically: false,
            sampleProvider: { _ in
                sampleCount += 1
                return .empty
            }
        )
        monitor.setPanelVisible(true)
        pump(seconds: 0.10)
        sampleCount = 0

        monitor.setExpandedMetric(nil)
        pump(seconds: 0.20)
        expect(sampleCount == 0)

        monitor.setExpandedMetric(.cpu)
        monitor.setExpandedMetric(.cpu)
        pump(seconds: 0.20)
        expect(sampleCount == 1)

        monitor.setExpandedMetric(.memory)
        pump(seconds: 0.05)
        monitor.setExpandedMetric(.disk)
        pump(seconds: 0.20)
        expect(sampleCount == 2)
        expect(monitor.expandedMetric == .disk)

        monitor.setExpandedMetric(nil)
        pump(seconds: 0.20)
        expect(sampleCount == 2)
    }

    private static func pump(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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
