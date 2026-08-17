import Foundation

@main
enum ThresholdLogicCheck {
    static func main() {
        checkHighThresholdState()
        checkLowThresholdState()
        checkCompactMeasurements()
        checkPersistence()
        print("Threshold logic checks passed")
    }

    private static func checkHighThresholdState() {
        let kind = ThresholdMetric.cpuUsage
        let rule = ThresholdRule(kind: kind, isEnabled: true, value: 80)
        var state = ThresholdTriggerState()

        expect(state.update(kind: kind, rule: rule, measurement: value(90, "90%", "CPU")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(91, "91%", "CPU")) == .activated)
        expect(state.isActive)

        // 77 is below the trigger but not below the 76% recovery line.
        expect(state.update(kind: kind, rule: rule, measurement: value(77, "77%", "CPU")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(75, "75%", "CPU")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(74, "74%", "CPU")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(73, "73%", "CPU")) == .recovered)
        expect(!state.isActive)
    }

    private static func checkLowThresholdState() {
        let kind = ThresholdMetric.batteryPercentage
        let rule = ThresholdRule(kind: kind, isEnabled: true, value: 20)
        var state = ThresholdTriggerState()

        expect(state.update(kind: kind, rule: rule, measurement: value(19, "19%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(18, "18%", "电池")) == .activated)
        expect(state.update(kind: kind, rule: rule, measurement: value(20.5, "21%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(22, "22%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(23, "23%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(24, "24%", "电池")) == .recovered)
    }

    private static func checkCompactMeasurements() {
        var snapshot = PerformanceSnapshot()
        snapshot.thermal.temperatures.cpu = TemperatureSummary(
            averageCelsius: 90,
            maximumCelsius: 94.4,
            sensorCount: 4
        )
        snapshot.network.download = 12 * 1_048_576
        snapshot.fans = [
            FanSnapshot(id: 0, speedRPM: 2_000),
            FanSnapshot(id: 1, speedRPM: 3_280)
        ]

        expect(ThresholdMetric.temperatureCPU.measurement(from: snapshot)?.valueText == "94°")
        expect(ThresholdMetric.temperatureCPU.measurement(from: snapshot)?.objectLabel == "CPU")
        expect(ThresholdMetric.networkDownload.measurement(from: snapshot)?.valueText == "12M/s")
        expect(ThresholdMetric.networkDownload.measurement(from: snapshot)?.objectLabel == "下载")
        expect(ThresholdMetric.fanSpeed.measurement(from: snapshot)?.valueText == "3280")
        expect(ThresholdMetric.fanSpeed.measurement(from: snapshot)?.objectLabel == "风扇 2")
    }

    private static func checkPersistence() {
        let suiteName = "com.xipiyoung.ColdHot.threshold-logic-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        settings.setThresholdEnabled(true, for: .cpuUsage)
        settings.setThresholdValue(91, for: .cpuUsage)

        let restored = MonitorSettings(defaults: defaults)
        expect(restored.thresholdRule(for: .cpuUsage).isEnabled)
        expect(restored.thresholdRule(for: .cpuUsage).value == 91)
        restored.reset()
        expect(!restored.thresholdRule(for: .cpuUsage).isEnabled)
        expect(restored.thresholdRule(for: .cpuUsage).value == ThresholdMetric.cpuUsage.defaultValue)
    }

    private static func value(_ rawValue: Double, _ text: String, _ object: String) -> ThresholdMeasurement {
        ThresholdMeasurement(rawValue: rawValue, valueText: text, objectLabel: object)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else { fatalError("Check failed", file: file, line: line) }
    }
}
