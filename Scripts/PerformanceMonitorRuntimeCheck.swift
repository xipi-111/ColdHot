import Foundation

@main
enum PerformanceMonitorRuntimeCheck {
    static func main() {
        let suiteName = "com.xipiyoung.ColdHot.performance-runtime-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        settings.applyPreset(.minimal)
        settings.sampleInterval = 1
        let monitor = PerformanceMonitor(settings: settings)
        monitor.setPanelVisible(true)
        monitor.setSettingsMonitoringActive(true)

        RunLoop.main.run(until: Date().addingTimeInterval(7))

        let selfSnapshot = monitor.selfResourceSnapshot
        expect(selfSnapshot.memoryBytes > 0)
        expect(selfSnapshot.cpuUsage.isFinite && selfSnapshot.cpuUsage >= 0)
        expect(
            selfSnapshot.wakeupsPerSecond.isFinite
                && selfSnapshot.wakeupsPerSecond >= 0
        )

        let cpuTrend = monitor.trendHistory[.cpu] ?? []
        expect(cpuTrend.count >= 2)
        if let first = cpuTrend.first, let last = cpuTrend.last {
            expect(last.timestamp.timeIntervalSince(first.timestamp) <= 62)
        }

        print(
            "Performance runtime checks passed; ColdHot CPU "
                + selfSnapshot.cpuUsage.formatted(
                    .number.precision(.fractionLength(2))
                )
                + "%, memory "
                + ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: selfSnapshot.memoryBytes),
                    countStyle: .memory
                )
                + ", wakeups "
                + selfSnapshot.wakeupsPerSecond.formatted(
                    .number.precision(.fractionLength(2))
                )
                + "/s"
        )
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
