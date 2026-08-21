import Foundation

@main
enum ThresholdLogicCheck {
    static func main() {
        checkRecommendedThresholdLevels()
        checkThresholdLevelNormalization()
        checkHighThresholdState()
        checkLowThresholdState()
        checkThermalThresholdSeverity()
        checkAlertPresentationRuntimeProjection()
        checkCompactMeasurements()
        checkLegacyRuleMigration()
        checkLegacySettingsMigration()
        checkThresholdColorComponents()
        checkPersistence()
        print("Threshold logic checks passed")
    }

    private static func checkRecommendedThresholdLevels() {
        let cpu = ThresholdRule.defaultRule(for: .cpuUsage)
        expect(cpu.value == 85)
        expect(cpu.level2Value == 90)
        expect(cpu.level3Value == 95)

        let network = ThresholdRule.defaultRule(for: .networkDownload)
        expect(network.value == 50)
        expect(network.level2Value == 75)
        expect(network.level3Value == 100)

        let fan = ThresholdRule.defaultRule(for: .fanSpeed)
        expect(fan.value == 5_000)
        expect(fan.level2Value == 5_500)
        expect(fan.level3Value == 6_000)

        let power = ThresholdRule.defaultRule(for: .systemPower)
        expect(power.value == 40)
        expect(power.level2Value == 50)
        expect(power.level3Value == 60)

        let battery = ThresholdRule.defaultRule(for: .batteryPercentage)
        expect(battery.value == 20)
        expect(battery.level2Value == 15)
        expect(battery.level3Value == 10)
    }

    private static func checkThresholdLevelNormalization() {
        let high = ThresholdRule(
            kind: .cpuUsage,
            isEnabled: true,
            value: 90,
            level2Value: 80,
            level3Value: 500
        )
        expect(high.value == 90)
        expect(high.level2Value == 90)
        expect(high.level3Value == 100)

        let low = ThresholdRule(
            kind: .batteryPercentage,
            isEnabled: true,
            value: 20,
            level2Value: 25,
            level3Value: -10
        )
        expect(low.value == 20)
        expect(low.level2Value == 20)
        expect(low.level3Value == 1)

        expect(high.severity(forActiveValue: 89) == .level1)
        expect(high.severity(forActiveValue: 90) == .level2)
        expect(high.severity(forActiveValue: 100) == .level3)
        let battery = ThresholdRule.defaultRule(for: .batteryPercentage)
        expect(battery.severity(forActiveValue: 16) == .level1)
        expect(battery.severity(forActiveValue: 15) == .level2)
        expect(battery.severity(forActiveValue: 10) == .level3)

        let thermal = ThresholdRule(
            kind: .thermalState,
            isEnabled: true,
            value: 2
        )
        expect(thermal.severity(forActiveValue: 1) == .level1)
        expect(thermal.severity(forActiveValue: 2) == .level2)
        expect(thermal.severity(forActiveValue: 3) == .level3)
    }

    private static func checkHighThresholdState() {
        let kind = ThresholdMetric.cpuUsage
        let rule = ThresholdRule(kind: kind, isEnabled: true, value: 80)
        var state = ThresholdTriggerState()
        let activatedAt = Date(timeIntervalSince1970: 123)

        expect(state.update(kind: kind, rule: rule, measurement: value(80, "80%", "CPU")) == .unchanged)
        expect(
            state.update(
                kind: kind,
                rule: rule,
                measurement: value(81, "81%", "CPU"),
                at: activatedAt
            ) == .activated
        )
        expect(state.isActive)
        expect(state.activatedAt == activatedAt)
        expect(state.latestSeverity == .level1)

        expect(state.update(kind: kind, rule: rule, measurement: value(85, "85%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level2)
        expect(state.update(kind: kind, rule: rule, measurement: value(91, "91%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level3)
        expect(state.update(kind: kind, rule: rule, measurement: value(82, "82%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level1)

        // 77 is below the trigger but not below the 76% recovery line.
        expect(state.update(kind: kind, rule: rule, measurement: value(77, "77%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(75, "75%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(74, "74%", "CPU")) == .unchanged)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(73, "73%", "CPU")) == .recovered)
        expect(!state.isActive)
        expect(state.activatedAt == nil)
        expect(state.latestSeverity == nil)
    }

    private static func checkLowThresholdState() {
        let kind = ThresholdMetric.batteryPercentage
        let rule = ThresholdRule(kind: kind, isEnabled: true, value: 20)
        var state = ThresholdTriggerState()

        expect(state.update(kind: kind, rule: rule, measurement: value(19, "19%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(18, "18%", "电池")) == .activated)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(15, "15%", "电池")) == .unchanged)
        expect(state.latestSeverity == .level2)
        expect(state.update(kind: kind, rule: rule, measurement: value(9, "9%", "电池")) == .unchanged)
        expect(state.latestSeverity == .level3)
        expect(state.update(kind: kind, rule: rule, measurement: value(18, "18%", "电池")) == .unchanged)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(20.5, "21%", "电池")) == .unchanged)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(22, "22%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(23, "23%", "电池")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(24, "24%", "电池")) == .recovered)
        expect(state.latestSeverity == nil)
    }

    private static func checkThermalThresholdSeverity() {
        let kind = ThresholdMetric.thermalState
        let rule = ThresholdRule(kind: kind, isEnabled: true, value: 1)
        var state = ThresholdTriggerState()

        expect(state.update(kind: kind, rule: rule, measurement: value(1, "偏热", "系统")) == .unchanged)
        expect(state.update(kind: kind, rule: rule, measurement: value(1, "偏热", "系统")) == .activated)
        expect(state.latestSeverity == .level1)
        expect(state.update(kind: kind, rule: rule, measurement: value(2, "较热", "系统")) == .unchanged)
        expect(state.latestSeverity == .level2)
        expect(state.update(kind: kind, rule: rule, measurement: value(3, "严重", "系统")) == .unchanged)
        expect(state.latestSeverity == .level3)
    }

    private static func checkAlertPresentationRuntimeProjection() {
        let cpuRule = ThresholdRule(kind: .cpuUsage, isEnabled: true, value: 80)
        let batteryRule = ThresholdRule(
            kind: .batteryPercentage,
            isEnabled: true,
            value: 20
        )
        let rules: [ThresholdMetric: ThresholdRule] = [
            .cpuUsage: cpuRule,
            .batteryPercentage: batteryRule
        ]
        var presentation = ThresholdAlertPresentationState()

        expect(!presentation.update([
            ThresholdEvaluation(
                kind: .cpuUsage,
                rule: cpuRule,
                measurement: value(80, "80%", "CPU")
            )
        ]).membershipChanged)
        expect(presentation.update([
            ThresholdEvaluation(
                kind: .cpuUsage,
                rule: cpuRule,
                measurement: value(81, "81%", "CPU")
            )
        ]).membershipChanged)
        expect(presentation.alerts(using: rules).map(\.kind) == [.cpuUsage])
        expect(presentation.visibleAlert(using: rules)?.severity == .level1)

        let severityOnly = presentation.update([
            ThresholdEvaluation(
                kind: .cpuUsage,
                rule: cpuRule,
                measurement: value(85, "85%", "CPU")
            )
        ])
        expect(!severityOnly.membershipChanged)
        expect(presentation.visibleAlert(using: rules)?.severity == .level2)

        expect(!presentation.update([
            ThresholdEvaluation(
                kind: .batteryPercentage,
                rule: batteryRule,
                measurement: value(19, "19%", "电池")
            )
        ]).membershipChanged)
        expect(presentation.update([
            ThresholdEvaluation(
                kind: .batteryPercentage,
                rule: batteryRule,
                measurement: value(18, "18%", "电池")
            )
        ]).membershipChanged)
        expect(
            presentation.alerts(using: rules).map(\.kind)
                == [.batteryPercentage, .cpuUsage]
        )
        expect(presentation.visibleAlert(using: rules)?.kind == .batteryPercentage)

        let rotated = presentation.advanceRotation(using: rules)
        expect(rotated?.kind == .cpuUsage)
        expect(presentation.alertRotationIndex == 1)

        let upgradedCPU = presentation.update([
            ThresholdEvaluation(
                kind: .cpuUsage,
                rule: cpuRule,
                measurement: value(91, "91%", "CPU")
            )
        ])
        expect(!upgradedCPU.membershipChanged)
        expect(presentation.alertRotationIndex == 1)
        expect(presentation.visibleAlert(using: rules)?.kind == .cpuUsage)
        expect(presentation.visibleAlert(using: rules)?.severity == .level3)

        let downgradedCPU = presentation.update([
            ThresholdEvaluation(
                kind: .cpuUsage,
                rule: cpuRule,
                measurement: value(82, "82%", "CPU")
            )
        ])
        expect(!downgradedCPU.membershipChanged)
        expect(presentation.alertRotationIndex == 1)
        expect(presentation.visibleAlert(using: rules)?.severity == .level1)
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

    private static func checkLegacyRuleMigration() {
        let legacyJSON = """
        [{"kind":"cpuUsage","isEnabled":true,"value":91}]
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([ThresholdRule].self, from: legacyJSON)
        let cpu = decoded[0]
        expect(cpu.kind == .cpuUsage)
        expect(cpu.isEnabled)
        expect(cpu.value == 91)
        expect(cpu.level2Value == 96)
        expect(cpu.level3Value == 100)

        let encoded = try! JSONEncoder().encode(decoded)
        let object = try! JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        expect(object[0]["value"] as? Double == 91)
        expect(object[0]["level2Value"] as? Double == 96)
        expect(object[0]["level3Value"] as? Double == 100)
    }

    private static func checkLegacySettingsMigration() {
        let suiteName = "com.xipiyoung.ColdHot.threshold-legacy-settings-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated legacy defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyJSON = """
        [{"kind":"cpuUsage","isEnabled":true,"value":91}]
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: "thresholdRules")
        defaults.set(true, forKey: "thresholdNotificationsEnabled")
        defaults.set(false, forKey: "thresholdRecoveryNotificationsEnabled")

        let migrated = MonitorSettings(defaults: defaults)
        let cpu = migrated.thresholdRule(for: .cpuUsage)
        expect(cpu.isEnabled)
        expect(cpu.value == 91)
        expect(cpu.level2Value == 96)
        expect(cpu.level3Value == 100)
        expect(migrated.thresholdNotificationsEnabled)
        expect(!migrated.thresholdRecoveryNotificationsEnabled)

        let storedData = defaults.data(forKey: "thresholdRules")!
        let storedObject = try! JSONSerialization.jsonObject(with: storedData) as! [[String: Any]]
        let storedCPU = storedObject.first { $0["kind"] as? String == "cpuUsage" }!
        expect(storedCPU["value"] as? Double == 91)
        expect(storedCPU["level2Value"] as? Double == 96)
        expect(storedCPU["level3Value"] as? Double == 100)
    }

    private static func checkThresholdColorComponents() {
        let bounded = ThresholdColorComponents(
            red: -0.5,
            green: 1.5,
            blue: .infinity,
            alpha: .nan
        )
        expect(bounded.red == 0)
        expect(bounded.green == 1)
        expect(bounded.blue == 1)
        expect(bounded.alpha == 1)

        let recommended = ThresholdSeverityColors.recommended
        expect(recommended.level1Custom == nil)
        expect(recommended.level2 == ThresholdColorComponents(red: 1, green: 0.8, blue: 0, alpha: 1))
        expect(recommended.level3 == ThresholdColorComponents(red: 1, green: 0.231, blue: 0.188, alpha: 1))
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
        settings.setThresholdValues(level1: 91, level2: 94, level3: 97, for: .cpuUsage)
        settings.setThresholdColor(
            ThresholdColorComponents(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9),
            for: .level1
        )
        settings.setThresholdColor(
            ThresholdColorComponents(red: 0.9, green: 0.7, blue: 0.1, alpha: 1),
            for: .level2
        )
        settings.setThresholdColor(
            ThresholdColorComponents(red: 0.8, green: 0.1, blue: 0.2, alpha: 0.8),
            for: .level3
        )
        settings.thresholdNotificationsEnabled = true
        settings.thresholdRecoveryNotificationsEnabled = false
        settings.completeOnboarding()
        settings.applyPreset(.diagnostic)

        let restored = MonitorSettings(defaults: defaults)
        expect(restored.thresholdRule(for: .cpuUsage).isEnabled)
        expect(restored.thresholdRule(for: .cpuUsage).value == 91)
        expect(restored.thresholdRule(for: .cpuUsage).level2Value == 94)
        expect(restored.thresholdRule(for: .cpuUsage).level3Value == 97)
        expect(
            restored.thresholdSeverityColors.level1Custom
                == ThresholdColorComponents(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9)
        )
        expect(
            restored.thresholdSeverityColors.level2
                == ThresholdColorComponents(red: 0.9, green: 0.7, blue: 0.1, alpha: 1)
        )
        expect(
            restored.thresholdSeverityColors.level3
                == ThresholdColorComponents(red: 0.8, green: 0.1, blue: 0.2, alpha: 0.8)
        )
        expect(restored.thresholdNotificationsEnabled)
        expect(!restored.thresholdRecoveryNotificationsEnabled)
        expect(restored.hasCompletedOnboarding)
        expect(restored.enabledMetrics == BuildVariant.availableMetrics)
        expect(restored.enabledDetails == BuildVariant.availableDetails)

        restored.applyPreset(.minimal)
        expect(restored.enabledMetrics.contains(.cpu))
        expect(restored.enabledMetrics.contains(.memory))
        expect(!restored.enabledMetrics.contains(.disk))
        restored.restoreRecommendedReadability()
        expect(restored.panelBackgroundDimOpacity == 0.35)
        expect(restored.panelCardOpacity == 0.65)
        expect(restored.panelPrimaryTextOpacity == 1)
        expect(restored.panelSecondaryTextOpacity == 0.85)
        expect(restored.panelProgressOpacity == 0.85)

        restored.reset()
        expect(!restored.thresholdRule(for: .cpuUsage).isEnabled)
        expect(restored.thresholdRule(for: .cpuUsage).value == ThresholdMetric.cpuUsage.defaultValue)
        expect(restored.thresholdRule(for: .cpuUsage).level2Value == 90)
        expect(restored.thresholdRule(for: .cpuUsage).level3Value == 95)
        expect(restored.thresholdSeverityColors == .recommended)
        expect(!restored.thresholdNotificationsEnabled)
        expect(restored.thresholdRecoveryNotificationsEnabled)
        expect(restored.hasCompletedOnboarding)
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
