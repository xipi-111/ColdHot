import Foundation
import Combine

final class PerformanceMonitor: ObservableObject {
    @Published private(set) var snapshot = PerformanceSnapshot.empty
    @Published private(set) var expandedMetric: MetricKind?

    private let queue = DispatchQueue(label: "com.xipiyoung.ColdHot.sampler", qos: .utility)
    private let sampler = SystemSampler()
    private var timer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()
    private var enabledMetrics: Set<MetricKind>
    private var enabledDetails: Set<MetricDetail>
    private var samplingExpandedMetric: MetricKind?

    init(settings: MonitorSettings) {
        enabledMetrics = settings.enabledMetrics
        enabledDetails = settings.enabledDetails
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
    }

    deinit {
        timer?.cancel()
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

    private func sampleNow() {
        let request = SamplingRequest(
            enabledMetrics: enabledMetrics,
            enabledDetails: enabledDetails,
            expandedMetric: samplingExpandedMetric
        )
        let newSnapshot = sampler.sample(request: request)
        DispatchQueue.main.async { [weak self] in
            self?.snapshot = newSnapshot
        }
    }
}
