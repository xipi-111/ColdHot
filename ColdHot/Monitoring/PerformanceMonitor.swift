import Foundation
import Combine

final class PerformanceMonitor: ObservableObject {
    @Published private(set) var snapshot = PerformanceSnapshot.empty
    @Published private(set) var expandedMetric: MetricKind?
    @Published private(set) var activeThresholdAlerts: [ThresholdAlert] = []
    @Published private(set) var visibleThresholdAlert: ThresholdAlert?

    private let queue = DispatchQueue(label: "com.xipiyoung.ColdHot.sampler", qos: .utility)
    private let sampler = SystemSampler()
    private var timer: DispatchSourceTimer?
    private var alertRotationTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()
    private var enabledMetrics: Set<MetricKind>
    private var enabledDetails: Set<MetricDetail>
    private var samplingExpandedMetric: MetricKind?
    private var thresholdRules: [ThresholdMetric: ThresholdRule]
    private var thresholdStates: [ThresholdMetric: ThresholdTriggerState] = [:]
    private var alertOrder: [ThresholdMetric] = []
    private var alertRotationIndex = 0
    private var lastBackgroundDetailSampleAt = Date.distantPast

    init(settings: MonitorSettings) {
        enabledMetrics = settings.enabledMetrics
        enabledDetails = settings.enabledDetails
        thresholdRules = settings.thresholdRules
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
            thresholdStates[$0]?.isActive == true
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
        let alerts = currentAlerts()
        if membershipChanged || resetAlertRotation {
            restartAlertRotation(alertCount: alerts.count)
        }
        let visibleAlert = alerts.isEmpty
            ? nil
            : alerts[min(alertRotationIndex, alerts.count - 1)]

        DispatchQueue.main.async { [weak self] in
            self?.snapshot = newSnapshot
            self?.activeThresholdAlerts = alerts
            self?.visibleThresholdAlert = visibleAlert
        }
    }

    private func applyThresholdRules(_ rules: [ThresholdMetric: ThresholdRule]) -> Bool {
        let changedKinds = Set(ThresholdMetric.allCases.filter {
            thresholdRules[$0] != rules[$0]
        })
        let removedActiveAlert = changedKinds.contains {
            thresholdStates[$0]?.isActive == true
        }
        thresholdRules = rules

        for kind in changedKinds {
            thresholdStates.removeValue(forKey: kind)
            alertOrder.removeAll { $0 == kind }
        }
        if changedKinds.contains(where: { $0.requiredDetail != nil }) {
            lastBackgroundDetailSampleAt = .distantPast
        }
        return removedActiveAlert
    }

    private func restartAlertRotation(alertCount: Int) {
        alertRotationTimer?.cancel()
        alertRotationTimer = nil
        alertRotationIndex = 0

        guard alertCount > 1 else { return }
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + 5, repeating: 5, leeway: .milliseconds(100))
        newTimer.setEventHandler { [weak self] in
            guard let self else { return }
            let alerts = self.currentAlerts()
            guard alerts.count > 1 else { return }
            self.alertRotationIndex = (self.alertRotationIndex + 1) % alerts.count
            let visibleAlert = alerts[self.alertRotationIndex]
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
        var membershipChanged = false
        var activatedKinds: [ThresholdMetric] = []

        for kind in ThresholdMetric.allCases where evaluatedKinds.contains(kind) {
            guard let rule = thresholdRules[kind], rule.isEnabled,
                  let measurement = kind.measurement(from: snapshot) else { continue }

            var state = thresholdStates[kind] ?? ThresholdTriggerState()
            let transition = state.update(kind: kind, rule: rule, measurement: measurement)
            if transition == .activated {
                activatedKinds.append(kind)
                membershipChanged = true
            } else if transition == .recovered {
                alertOrder.removeAll { $0 == kind }
                membershipChanged = true
            }

            thresholdStates[kind] = state
        }

        for kind in activatedKinds.reversed() {
            alertOrder.removeAll { $0 == kind }
            alertOrder.insert(kind, at: 0)
        }
        return membershipChanged
    }

    private func currentAlerts() -> [ThresholdAlert] {
        alertOrder.compactMap { kind in
            guard let state = thresholdStates[kind], state.isActive,
                  let measurement = state.latestMeasurement else { return nil }
            return ThresholdAlert(kind: kind, measurement: measurement)
        }
    }
}
