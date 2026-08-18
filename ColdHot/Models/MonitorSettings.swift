import Foundation
import Combine

final class MonitorSettings: ObservableObject {
    static let defaultMetrics: Set<MetricKind> = [
        .cpu, .gpu, .memory, .network, .thermal
    ]
    static let defaultPanelBackgroundDimOpacity = 0.35
    static let defaultPanelCardOpacity = 1.0
    static let defaultPanelPrimaryTextOpacity = 1.0
    static let defaultPanelSecondaryTextOpacity = 1.0
    static let defaultPanelProgressOpacity = 1.0

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

    @Published private(set) var isPanelBackgroundEnabled: Bool

    @Published private(set) var panelBackgroundDimOpacity: Double

    @Published private(set) var panelCardOpacity: Double

    @Published private(set) var panelPrimaryTextOpacity: Double

    @Published private(set) var panelSecondaryTextOpacity: Double

    @Published private(set) var panelProgressOpacity: Double

    @Published private(set) var thresholdRules: [ThresholdMetric: ThresholdRule] {
        didSet { persistThresholdRules() }
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

        isPanelBackgroundEnabled = defaults.object(forKey: Keys.isPanelBackgroundEnabled) as? Bool
            ?? false

        if defaults.object(forKey: Keys.panelBackgroundDimOpacity) != nil {
            let storedOpacity = defaults.double(forKey: Keys.panelBackgroundDimOpacity)
            panelBackgroundDimOpacity = storedOpacity.isFinite
                ? min(max(storedOpacity, 0), 0.70)
                : Self.defaultPanelBackgroundDimOpacity
        } else {
            panelBackgroundDimOpacity = Self.defaultPanelBackgroundDimOpacity
        }

        if defaults.object(forKey: Keys.panelCardOpacity) != nil {
            let storedOpacity = defaults.double(forKey: Keys.panelCardOpacity)
            panelCardOpacity = storedOpacity.isFinite
                ? min(max(storedOpacity, 0.10), 1)
                : Self.defaultPanelCardOpacity
        } else {
            panelCardOpacity = Self.defaultPanelCardOpacity
        }

        panelPrimaryTextOpacity = Self.readPanelOpacity(
            from: defaults,
            key: Keys.panelPrimaryTextOpacity,
            legacyKey: Keys.panelTextOpacity,
            defaultValue: Self.defaultPanelPrimaryTextOpacity
        )
        panelSecondaryTextOpacity = Self.readPanelOpacity(
            from: defaults,
            key: Keys.panelSecondaryTextOpacity,
            legacyKey: Keys.panelTextOpacity,
            defaultValue: Self.defaultPanelSecondaryTextOpacity
        )
        panelProgressOpacity = Self.readPanelOpacity(
            from: defaults,
            key: Keys.panelProgressOpacity,
            defaultValue: Self.defaultPanelProgressOpacity
        )

        let defaultRules = Dictionary(uniqueKeysWithValues: ThresholdMetric.allCases.map {
            ($0, ThresholdRule.defaultRule(for: $0))
        })
        if let data = defaults.data(forKey: Keys.thresholdRules),
           let storedRules = try? JSONDecoder().decode([ThresholdRule].self, from: data) {
            thresholdRules = storedRules.reduce(into: defaultRules) { result, rule in
                result[rule.kind] = ThresholdRule(
                    kind: rule.kind,
                    isEnabled: rule.isEnabled,
                    value: rule.kind.clamped(rule.value)
                )
            }
        } else {
            thresholdRules = defaultRules
        }
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

    func thresholdRule(for kind: ThresholdMetric) -> ThresholdRule {
        thresholdRules[kind] ?? .defaultRule(for: kind)
    }

    func setThresholdEnabled(_ enabled: Bool, for kind: ThresholdMetric) {
        guard BuildVariant.availableThresholdMetrics.contains(kind) else { return }
        var updated = thresholdRules
        var rule = thresholdRule(for: kind)
        rule.isEnabled = enabled
        updated[kind] = rule
        thresholdRules = updated
    }

    func setThresholdValue(_ value: Double, for kind: ThresholdMetric) {
        guard BuildVariant.availableThresholdMetrics.contains(kind), value.isFinite else { return }
        var updated = thresholdRules
        var rule = thresholdRule(for: kind)
        rule.value = kind.clamped(value)
        updated[kind] = rule
        thresholdRules = updated
    }

    func setPanelBackgroundEnabled(_ enabled: Bool) {
        isPanelBackgroundEnabled = enabled
        defaults.set(enabled, forKey: Keys.isPanelBackgroundEnabled)
    }

    func setPanelBackgroundDimOpacity(_ opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0), 0.70)
        panelBackgroundDimOpacity = clamped
        defaults.set(clamped, forKey: Keys.panelBackgroundDimOpacity)
    }

    func setPanelCardOpacity(_ opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0.10), 1)
        panelCardOpacity = clamped
        defaults.set(clamped, forKey: Keys.panelCardOpacity)
    }

    func setPanelPrimaryTextOpacity(_ opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0.50), 1)
        panelPrimaryTextOpacity = clamped
        defaults.set(clamped, forKey: Keys.panelPrimaryTextOpacity)
    }

    func setPanelSecondaryTextOpacity(_ opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0.50), 1)
        panelSecondaryTextOpacity = clamped
        defaults.set(clamped, forKey: Keys.panelSecondaryTextOpacity)
    }

    func setPanelProgressOpacity(_ opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0.50), 1)
        panelProgressOpacity = clamped
        defaults.set(clamped, forKey: Keys.panelProgressOpacity)
    }

    func reset() {
        enabledMetrics = Self.defaultMetrics.intersection(BuildVariant.availableMetrics)
        enabledDetails = MetricDetail.defaults
        sampleInterval = 2.0
        showDockQuickControl = true
        setPanelBackgroundEnabled(false)
        setPanelBackgroundDimOpacity(Self.defaultPanelBackgroundDimOpacity)
        setPanelCardOpacity(Self.defaultPanelCardOpacity)
        setPanelPrimaryTextOpacity(Self.defaultPanelPrimaryTextOpacity)
        setPanelSecondaryTextOpacity(Self.defaultPanelSecondaryTextOpacity)
        setPanelProgressOpacity(Self.defaultPanelProgressOpacity)
        thresholdRules = Dictionary(uniqueKeysWithValues: ThresholdMetric.allCases.map {
            ($0, ThresholdRule.defaultRule(for: $0))
        })
    }

    private func persistMetrics() {
        defaults.set(enabledMetrics.map(\.rawValue).sorted(), forKey: Keys.enabledMetrics)
    }

    private func persistDetails() {
        defaults.set(enabledDetails.map(\.rawValue).sorted(), forKey: Keys.enabledDetails)
    }

    private func persistThresholdRules() {
        let rules = thresholdRules.values.sorted { $0.kind.rawValue < $1.kind.rawValue }
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Keys.thresholdRules)
        }
    }

    private static func readPanelOpacity(
        from defaults: UserDefaults,
        key: String,
        legacyKey: String? = nil,
        defaultValue: Double
    ) -> Double {
        let storedKey: String?
        if defaults.object(forKey: key) != nil {
            storedKey = key
        } else if let legacyKey, defaults.object(forKey: legacyKey) != nil {
            storedKey = legacyKey
        } else {
            storedKey = nil
        }

        guard let storedKey else { return defaultValue }
        let storedOpacity = defaults.double(forKey: storedKey)
        guard storedOpacity.isFinite else { return defaultValue }
        return min(max(storedOpacity, 0.50), 1)
    }

    private enum Keys {
        static let enabledMetrics = "enabledMetrics"
        static let enabledDetails = "enabledDetails"
        static let sampleInterval = "sampleInterval"
        static let showDockQuickControl = "showDockQuickControl"
        static let isPanelBackgroundEnabled = "isPanelBackgroundEnabled"
        static let panelBackgroundDimOpacity = "panelBackgroundDimOpacity"
        static let panelCardOpacity = "panelCardOpacity"
        static let panelPrimaryTextOpacity = "panelPrimaryTextOpacity"
        static let panelSecondaryTextOpacity = "panelSecondaryTextOpacity"
        static let panelProgressOpacity = "panelProgressOpacity"
        static let panelTextOpacity = "panelTextOpacity"
        static let thresholdRules = "thresholdRules"
    }
}
