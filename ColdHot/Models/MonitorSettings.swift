import Foundation
import Combine

final class MonitorSettings: ObservableObject {
    static let defaultMetrics: Set<MetricKind> = [
        .cpu, .gpu, .memory, .network, .thermal
    ]

    @Published private(set) var enabledMetrics: Set<MetricKind> {
        didSet { persistMetrics() }
    }

    @Published private(set) var enabledDetails: Set<MetricDetail> {
        didSet { persistDetails() }
    }

    @Published var sampleInterval: Double {
        didSet { defaults.set(sampleInterval, forKey: Keys.sampleInterval) }
    }

    @Published var showDockQuickControl: Bool {
        didSet { defaults.set(showDockQuickControl, forKey: Keys.showDockQuickControl) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValues = defaults.array(forKey: Keys.enabledMetrics) as? [String] {
            var migrated = Set(rawValues.compactMap(MetricKind.init(rawValue:)))
            if rawValues.contains("load") || rawValues.contains("topProcesses") {
                migrated.insert(.cpu)
            }
            enabledMetrics = migrated.intersection(BuildVariant.availableMetrics)
        } else {
            enabledMetrics = Self.defaultMetrics.intersection(BuildVariant.availableMetrics)
        }

        if let rawValues = defaults.array(forKey: Keys.enabledDetails) as? [String] {
            enabledDetails = Set(rawValues.compactMap(MetricDetail.init(rawValue:)))
                .intersection(BuildVariant.availableDetails)
        } else {
            enabledDetails = MetricDetail.defaults
        }

        let storedInterval = defaults.double(forKey: Keys.sampleInterval)
        sampleInterval = [1.0, 2.0, 5.0].contains(storedInterval) ? storedInterval : 2.0

        showDockQuickControl = defaults.object(forKey: Keys.showDockQuickControl) as? Bool ?? true
    }

    func isEnabled(_ metric: MetricKind) -> Bool {
        enabledMetrics.contains(metric)
    }

    func isDetailEnabled(_ detail: MetricDetail) -> Bool {
        enabledDetails.contains(detail)
    }

    func setEnabled(_ enabled: Bool, for metric: MetricKind) {
        guard BuildVariant.availableMetrics.contains(metric) else { return }
        var updated = enabledMetrics
        if enabled {
            updated.insert(metric)
        } else {
            updated.remove(metric)
        }
        enabledMetrics = updated
    }

    func setDetailEnabled(_ enabled: Bool, for detail: MetricDetail) {
        guard BuildVariant.availableDetails.contains(detail) else { return }
        var updated = enabledDetails
        if enabled {
            updated.insert(detail)
        } else {
            updated.remove(detail)
        }
        enabledDetails = updated
    }

    func reset() {
        enabledMetrics = Self.defaultMetrics.intersection(BuildVariant.availableMetrics)
        enabledDetails = MetricDetail.defaults
        sampleInterval = 2.0
        showDockQuickControl = true
    }

    private func persistMetrics() {
        defaults.set(enabledMetrics.map(\.rawValue).sorted(), forKey: Keys.enabledMetrics)
    }

    private func persistDetails() {
        defaults.set(enabledDetails.map(\.rawValue).sorted(), forKey: Keys.enabledDetails)
    }

    private enum Keys {
        static let enabledMetrics = "enabledMetrics"
        static let enabledDetails = "enabledDetails"
        static let sampleInterval = "sampleInterval"
        static let showDockQuickControl = "showDockQuickControl"
    }
}
