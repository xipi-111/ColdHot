import Foundation
import Combine
import Darwin
import UserNotifications

final class PerformanceMonitor: ObservableObject {
    @Published private(set) var snapshot = PerformanceSnapshot.empty
    @Published private(set) var expandedMetric: MetricKind?
    @Published private(set) var activeThresholdAlerts: [ThresholdAlert] = []
    @Published private(set) var visibleThresholdAlert: ThresholdAlert?
    @Published private(set) var trendHistory: [MetricKind: [MetricTrendPoint]] = [:]
    @Published private(set) var selfResourceSnapshot = SelfResourceSnapshot()

    private let queue = DispatchQueue(label: "com.xipiyoung.ColdHot.sampler", qos: .utility)
    private let sampler = SystemSampler()
    private var timer: DispatchSourceTimer?
    private var alertRotationTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()
    private var enabledMetrics: Set<MetricKind>
    private var enabledDetails: Set<MetricDetail>
    private var samplingExpandedMetric: MetricKind?
    private var thresholdRules: [ThresholdMetric: ThresholdRule]
    private var thresholdPresentation = ThresholdAlertPresentationState()
    private var lastBackgroundDetailSampleAt = Date.distantPast
    private var trendHistoryStorage: [MetricKind: [MetricTrendPoint]] = [:]
    private var previousSelfResourceCounters: SelfResourceCounters?
    private var lastSelfResourceSampleAt = Date.distantPast
    private var notificationsEnabled: Bool
    private var recoveryNotificationsEnabled: Bool
    private let notificationController = ThresholdNotificationController()
    private let processCPUAccounting = ProcessCPUAccounting.current

    init(settings: MonitorSettings) {
        enabledMetrics = settings.enabledMetrics
        enabledDetails = settings.enabledDetails
        thresholdRules = settings.thresholdRules
        notificationsEnabled = settings.thresholdNotificationsEnabled
        recoveryNotificationsEnabled = settings.thresholdRecoveryNotificationsEnabled
        start(interval: settings.sampleInterval)

        settings.$sampleInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in self?.start(interval: interval) }
            .store(in: &cancellables)

        settings.$enabledMetrics
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] metrics in
                self?.queue.async {
                    self?.enabledMetrics = metrics
                    self?.sampleNow()
                }
            }
            .store(in: &cancellables)

        settings.$enabledDetails
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] details in
                self?.queue.async {
                    self?.enabledDetails = details
                    self?.sampleNow()
                }
            }
            .store(in: &cancellables)

        settings.$thresholdRules
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] rules in
                self?.queue.async {
                    guard let self else { return }
                    let needsRotationReset = self.applyThresholdRules(rules)
                    self.sampleNow(resetAlertRotation: needsRotationReset)
                }
            }
            .store(in: &cancellables)

        settings.$thresholdNotificationsEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.queue.async { self?.notificationsEnabled = enabled }
            }
            .store(in: &cancellables)

        settings.$thresholdRecoveryNotificationsEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.queue.async { self?.recoveryNotificationsEnabled = enabled }
            }
            .store(in: &cancellables)
    }

    deinit {
        timer?.cancel()
        alertRotationTimer?.cancel()
    }

    func setExpandedMetric(_ metric: MetricKind?) {
        expandedMetric = metric
        queue.async { [weak self] in
            self?.samplingExpandedMetric = metric
            self?.queue.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self?.sampleNow()
            }
        }
    }

    func probeCapabilities() {
        queue.async { [weak self] in
            guard let self else { return }
            let requestedSensorDetails: Set<MetricDetail> = Set([
                .thermalCPU,
                .thermalGPU,
                .thermalMemory,
                .thermalStorage,
                .thermalBattery,
                .thermalAirflow,
                .thermalWireless,
                .thermalPMU,
                .batteryElectrical
            ])
            let sensorDetails = requestedSensorDetails.intersection(
                BuildVariant.availableDetails
            )
            let request = SamplingRequest(
                enabledMetrics: BuildVariant.availableMetrics,
                enabledDetails: Set<MetricDetail>(),
                expandedMetric: nil,
                backgroundMetrics: Set([.gpu, .thermal, .battery]),
                backgroundDetails: sensorDetails
            )
            let capabilitySnapshot = self.sampler.sample(request: request)
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = capabilitySnapshot
            }
        }
    }

    private func start(interval: TimeInterval) {
        timer?.cancel()
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(200))
        newTimer.setEventHandler { [weak self] in self?.sampleNow() }
        timer = newTimer
        newTimer.resume()
    }

    private func sampleNow(resetAlertRotation: Bool = false) {
        let now = Date()
        let enabledThresholdKinds = Set(thresholdRules.values.compactMap { rule in
            rule.isEnabled && BuildVariant.availableThresholdMetrics.contains(rule.kind)
                ? rule.kind
                : nil
        })
        let detailThresholdKinds = enabledThresholdKinds.filter { $0.requiredDetail != nil }
        let activeDetailKinds = detailThresholdKinds.filter {
            thresholdPresentation.isActive($0)
        }
        let isBackgroundDetailSampleDue = !detailThresholdKinds.isEmpty
            && now.timeIntervalSince(lastBackgroundDetailSampleAt) >= 5

        var requestedDetailKinds = activeDetailKinds
        if isBackgroundDetailSampleDue {
            requestedDetailKinds.formUnion(detailThresholdKinds)
            lastBackgroundDetailSampleAt = now
        }

        let backgroundDetails = Set(requestedDetailKinds.compactMap(\.requiredDetail))
        let primaryThresholdKinds = enabledThresholdKinds.filter { $0.requiredDetail == nil }
        let backgroundMetrics = Set(
            primaryThresholdKinds.map(\.metric) + requestedDetailKinds.map(\.metric)
        )
        let request = SamplingRequest(
            enabledMetrics: enabledMetrics,
            enabledDetails: enabledDetails,
            expandedMetric: samplingExpandedMetric,
            backgroundMetrics: backgroundMetrics,
            backgroundDetails: backgroundDetails
        )
        let newSnapshot = sampler.sample(request: request)

        let evaluatedKinds = enabledThresholdKinds.filter { kind in
            guard let detail = kind.requiredDetail else { return true }
            return request.includes(detail)
        }
        let membershipChanged = updateThresholdStates(
            with: newSnapshot,
            evaluatedKinds: evaluatedKinds
        )
        let alerts = thresholdPresentation.alerts(using: thresholdRules)
        if membershipChanged || resetAlertRotation {
            restartAlertRotation(alertCount: alerts.count)
        }
        let visibleAlert = thresholdPresentation.visibleAlert(using: thresholdRules)
        let updatedTrendHistory = updateTrendHistory(
            with: newSnapshot,
            metrics: request.enabledMetrics.union(request.backgroundMetrics),
            at: now
        )
        let updatedSelfResource = updateSelfResourceIfNeeded(at: now)

        DispatchQueue.main.async { [weak self] in
            self?.snapshot = newSnapshot
            self?.activeThresholdAlerts = alerts
            self?.visibleThresholdAlert = visibleAlert
            self?.trendHistory = updatedTrendHistory
            if let updatedSelfResource {
                self?.selfResourceSnapshot = updatedSelfResource
            }
        }
    }

    private func applyThresholdRules(_ rules: [ThresholdMetric: ThresholdRule]) -> Bool {
        let changedKinds = Set(ThresholdMetric.allCases.filter {
            thresholdRules[$0] != rules[$0]
        })
        thresholdRules = rules
        let removedActiveAlert = thresholdPresentation.remove(changedKinds)
        if changedKinds.contains(where: { $0.requiredDetail != nil }) {
            lastBackgroundDetailSampleAt = .distantPast
        }
        return removedActiveAlert
    }

    private func restartAlertRotation(alertCount: Int) {
        alertRotationTimer?.cancel()
        alertRotationTimer = nil
        thresholdPresentation.resetRotation()

        guard alertCount > 1 else { return }
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + 5, repeating: 5, leeway: .milliseconds(100))
        newTimer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let visibleAlert = self.thresholdPresentation.advanceRotation(
                using: self.thresholdRules
            ) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.visibleThresholdAlert = visibleAlert
            }
        }
        alertRotationTimer = newTimer
        newTimer.resume()
    }

    private func updateThresholdStates(
        with snapshot: PerformanceSnapshot,
        evaluatedKinds: Set<ThresholdMetric>
    ) -> Bool {
        let evaluations = ThresholdMetric.allCases.compactMap { kind -> ThresholdEvaluation? in
            guard evaluatedKinds.contains(kind) else { return nil }
            guard let rule = thresholdRules[kind], rule.isEnabled,
                  let measurement = kind.measurement(from: snapshot) else { return nil }
            return ThresholdEvaluation(kind: kind, rule: rule, measurement: measurement)
        }
        let update = thresholdPresentation.update(evaluations)
        for change in update.changes {
            if change.transition == .activated {
                if notificationsEnabled {
                    notificationController.sendActivated(
                        kind: change.kind,
                        measurement: change.measurement,
                        threshold: change.thresholdValue
                    )
                }
            } else if change.transition == .recovered {
                if notificationsEnabled && recoveryNotificationsEnabled {
                    notificationController.sendRecovered(
                        kind: change.kind,
                        measurement: change.measurement
                    )
                }
            }
        }
        return update.membershipChanged
    }

    private func updateTrendHistory(
        with snapshot: PerformanceSnapshot,
        metrics: Set<MetricKind>,
        at now: Date
    ) -> [MetricKind: [MetricTrendPoint]] {
        let cutoff = now.addingTimeInterval(-60)
        for metric in MetricKind.allCases where metrics.contains(metric) {
            guard let value = trendValue(for: metric, snapshot: snapshot),
                  value.isFinite else { continue }
            var points = trendHistoryStorage[metric, default: []]
            points.removeAll { $0.timestamp < cutoff }
            points.append(MetricTrendPoint(timestamp: now, value: value))
            trendHistoryStorage[metric] = points
        }

        for metric in trendHistoryStorage.keys where !metrics.contains(metric) {
            trendHistoryStorage[metric]?.removeAll { $0.timestamp < cutoff }
        }
        return trendHistoryStorage
    }

    private func trendValue(
        for metric: MetricKind,
        snapshot: PerformanceSnapshot
    ) -> Double? {
        switch metric {
        case .cpu:
            snapshot.cpu.usage
        case .gpu:
            snapshot.gpu.usage
        case .memory:
            snapshot.memory.total > 0
                ? Double(snapshot.memory.used) / Double(snapshot.memory.total) * 100
                : nil
        case .disk:
            (snapshot.disk.read + snapshot.disk.write) / 1_048_576
        case .network:
            (snapshot.network.download + snapshot.network.upload) / 1_048_576
        case .thermal:
            thermalTrendValue(snapshot.thermal)
        case .battery:
            snapshot.battery?.percentage
        }
    }

    private func thermalTrendValue(_ thermal: ThermalSnapshot) -> Double {
        switch thermal.state {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    private func updateSelfResourceIfNeeded(at now: Date) -> SelfResourceSnapshot? {
        guard now.timeIntervalSince(lastSelfResourceSampleAt) >= 5 else { return nil }
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            pointer.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        let counters = SelfResourceCounters(
            cpuTicks: usage.ri_user_time &+ usage.ri_system_time,
            wakeups: usage.ri_pkg_idle_wkups &+ usage.ri_interrupt_wkups,
            memoryBytes: usage.ri_phys_footprint,
            timestamp: now
        )
        defer {
            previousSelfResourceCounters = counters
            lastSelfResourceSampleAt = now
        }

        guard let previous = previousSelfResourceCounters else {
            return SelfResourceSnapshot(
                memoryBytes: counters.memoryBytes,
                timestamp: now
            )
        }
        let elapsed = now.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return nil }
        let processCPUUsage = counters.cpuTicks >= previous.cpuTicks
            ? processCPUAccounting.cpuUsage(
                deltaTicks: counters.cpuTicks - previous.cpuTicks,
                elapsedSeconds: elapsed
            )
            : 0
        let cpuUsage = ProcessCPUAccounting.wholeMachineUsage(
            processUsage: processCPUUsage,
            logicalProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
        let wakeups = counters.wakeups >= previous.wakeups
            ? Double(counters.wakeups - previous.wakeups) / elapsed
            : 0
        return SelfResourceSnapshot(
            cpuUsage: cpuUsage,
            memoryBytes: counters.memoryBytes,
            wakeupsPerSecond: wakeups,
            timestamp: now
        )
    }

}

private struct SelfResourceCounters {
    let cpuTicks: UInt64
    let wakeups: UInt64
    let memoryBytes: UInt64
    let timestamp: Date
}

final class ThresholdNotificationController {
    private var lastActivationSentAt: [ThresholdMetric: Date] = [:]
    private let activationCooldown: TimeInterval = 10 * 60

    static func requestAuthorization(
        completion: @escaping (Bool) -> Void
    ) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, _ in
            completion(granted)
        }
    }

    func sendActivated(
        kind: ThresholdMetric,
        measurement: ThresholdMeasurement,
        threshold: Double
    ) {
        let now = Date()
        if let lastSent = lastActivationSentAt[kind],
           now.timeIntervalSince(lastSent) < activationCooldown {
            return
        }
        lastActivationSentAt[kind] = now

        let content = UNMutableNotificationContent()
        content.title = "\(kind.title)达到阈值"
        content.body = "当前 \(measurement.valueText)，设定阈值 \(formattedThreshold(kind, threshold))."
        content.sound = .default
        add(content, identifier: "coldhot.threshold.\(kind.rawValue).\(now.timeIntervalSince1970)")
    }

    func sendRecovered(
        kind: ThresholdMetric,
        measurement: ThresholdMeasurement
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(kind.title)已恢复"
        content.body = "当前读数为 \(measurement.valueText)。"
        add(
            content,
            identifier: "coldhot.recovered.\(kind.rawValue).\(Date().timeIntervalSince1970)"
        )
    }

    private func add(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func formattedThreshold(
        _ kind: ThresholdMetric,
        _ value: Double
    ) -> String {
        if kind == .thermalState {
            switch Int(value) {
            case 1: return "偏热"
            case 2: return "较热"
            case 3: return "严重"
            default: return "正常"
            }
        }
        let numeric = value.rounded() == value
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(1)))
        return numeric + kind.unit
    }
}
