import Foundation

enum ThresholdDirection {
    case above
    case below
}

enum ThresholdSeverity: Int, CaseIterable, Codable, Identifiable {
    case level1 = 1
    case level2 = 2
    case level3 = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .level1: "一级"
        case .level2: "二级"
        case .level3: "三级"
        }
    }
}

struct ThresholdColorComponents: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = Self.bounded(red, fallback: 0)
        self.green = Self.bounded(green, fallback: 0)
        self.blue = Self.bounded(blue, fallback: 0)
        self.alpha = Self.bounded(alpha, fallback: 1)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decode(Double.self, forKey: .alpha)
        )
    }

    private static func bounded(_ value: Double, fallback: Double) -> Double {
        if value.isNaN { return fallback }
        if value == .infinity { return 1 }
        if value == -.infinity { return 0 }
        return min(max(value, 0), 1)
    }
}

struct ThresholdSeverityColors: Codable, Equatable {
    var level1Custom: ThresholdColorComponents?
    var level2: ThresholdColorComponents
    var level3: ThresholdColorComponents

    static let recommended = ThresholdSeverityColors(
        level1Custom: nil,
        level2: ThresholdColorComponents(red: 1, green: 0.8, blue: 0, alpha: 1),
        level3: ThresholdColorComponents(red: 1, green: 0.231, blue: 0.188, alpha: 1)
    )
}

fileprivate struct ThresholdLevelValues {
    let level1: Double
    let level2: Double
    let level3: Double
}

enum ThresholdMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case cpuUsage
    case gpuUsage
    case memoryUsage
    case networkDownload
    case networkUpload
    case diskRead
    case diskWrite
    case thermalState
    case batteryPercentage
    case temperatureCPU
    case temperatureGPU
    case temperatureMemory
    case temperatureStorage
    case temperatureBattery
    case temperatureAirflow
    case temperatureWireless
    case temperaturePowerManagement
    case fanSpeed
    case systemPower
    case batteryPower

    var id: String { rawValue }

    var metric: MetricKind {
        switch self {
        case .cpuUsage: .cpu
        case .gpuUsage: .gpu
        case .memoryUsage: .memory
        case .networkDownload, .networkUpload: .network
        case .diskRead, .diskWrite: .disk
        case .thermalState, .temperatureCPU, .temperatureGPU, .temperatureMemory,
             .temperatureStorage, .temperatureBattery, .temperatureAirflow,
             .temperatureWireless, .temperaturePowerManagement, .fanSpeed: .thermal
        case .batteryPercentage, .systemPower, .batteryPower: .battery
        }
    }

    var requiredDetail: MetricDetail? {
        switch self {
        case .temperatureCPU: .thermalCPU
        case .temperatureGPU: .thermalGPU
        case .temperatureMemory: .thermalMemory
        case .temperatureStorage: .thermalStorage
        case .temperatureBattery: .thermalBattery
        case .temperatureAirflow: .thermalAirflow
        case .temperatureWireless: .thermalWireless
        case .temperaturePowerManagement: .thermalPMU
        case .systemPower, .batteryPower: .batteryElectrical
        default: nil
        }
    }

    var title: String {
        switch self {
        case .cpuUsage: "CPU 使用率"
        case .gpuUsage: "GPU 使用率"
        case .memoryUsage: "内存使用率"
        case .networkDownload: "下载速度"
        case .networkUpload: "上传速度"
        case .diskRead: "磁盘读取"
        case .diskWrite: "磁盘写入"
        case .thermalState: "系统热状态"
        case .batteryPercentage: "电池低电量"
        case .temperatureCPU: "CPU 温度"
        case .temperatureGPU: "GPU 温度"
        case .temperatureMemory: "内存温度"
        case .temperatureStorage: "NAND 温度"
        case .temperatureBattery: "电池温度"
        case .temperatureAirflow: "风道温度"
        case .temperatureWireless: "Wi-Fi 温度"
        case .temperaturePowerManagement: "电源管理温度"
        case .fanSpeed: "风扇转速"
        case .systemPower: "整机功率"
        case .batteryPower: "电池功率"
        }
    }

    var explanation: String {
        switch self {
        case .batteryPercentage:
            "低于或等于设定电量时显示"
        case .thermalState:
            "达到设定热压力等级时显示"
        case .temperatureCPU, .temperatureGPU, .temperatureMemory, .temperatureStorage,
             .temperatureBattery, .temperatureAirflow, .temperatureWireless,
             .temperaturePowerManagement, .fanSpeed, .systemPower, .batteryPower:
            "开启后会按需启动后台传感器采样"
        default:
            "高于或等于设定数值时显示"
        }
    }

    var unit: String {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryPercentage: "%"
        case .networkDownload, .networkUpload, .diskRead, .diskWrite: "MB/s"
        case .temperatureCPU, .temperatureGPU, .temperatureMemory, .temperatureStorage,
             .temperatureBattery, .temperatureAirflow, .temperatureWireless,
             .temperaturePowerManagement: "°C"
        case .fanSpeed: "RPM"
        case .systemPower, .batteryPower: "W"
        case .thermalState: ""
        }
    }

    var defaultValue: Double {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage: 85
        case .networkDownload: 50
        case .networkUpload: 20
        case .diskRead, .diskWrite: 100
        case .thermalState: 2
        case .batteryPercentage: 20
        case .temperatureCPU, .temperatureGPU, .temperaturePowerManagement: 90
        case .temperatureMemory: 80
        case .temperatureStorage: 75
        case .temperatureBattery: 45
        case .temperatureAirflow: 50
        case .temperatureWireless: 70
        case .fanSpeed: 5_000
        case .systemPower: 40
        case .batteryPower: 20
        }
    }

    var validRange: ClosedRange<Double> {
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryPercentage: 1...100
        case .networkDownload, .networkUpload, .diskRead, .diskWrite: 0.1...10_000
        case .thermalState: 1...3
        case .temperatureCPU, .temperatureGPU, .temperatureMemory, .temperatureStorage,
             .temperatureBattery, .temperatureAirflow, .temperatureWireless,
             .temperaturePowerManagement: 20...130
        case .fanSpeed: 500...12_000
        case .systemPower, .batteryPower: 1...300
        }
    }

    var direction: ThresholdDirection {
        self == .batteryPercentage ? .below : .above
    }

    func clamped(_ value: Double) -> Double {
        min(max(value, validRange.lowerBound), validRange.upperBound)
    }

    func isTriggered(value: Double, threshold: Double) -> Bool {
        switch direction {
        case .above: value >= threshold
        case .below: value <= threshold
        }
    }

    func isRecovered(value: Double, threshold: Double) -> Bool {
        switch direction {
        case .above:
            value < threshold * 0.95
        case .below:
            value > min(100, threshold * 1.05)
        }
    }

    fileprivate func recommendedThresholdLevels(primary: Double) -> ThresholdLevelValues {
        let primary = primary.isFinite ? clamped(primary) : defaultValue
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage,
             .temperatureCPU, .temperatureGPU, .temperatureMemory, .temperatureStorage,
             .temperatureBattery, .temperatureAirflow, .temperatureWireless,
             .temperaturePowerManagement:
            return normalizedThresholdLevels(primary, primary + 5, primary + 10)
        case .networkDownload, .networkUpload, .diskRead, .diskWrite:
            return normalizedThresholdLevels(primary, primary * 1.5, primary * 2)
        case .fanSpeed:
            return normalizedThresholdLevels(primary, primary + 500, primary + 1_000)
        case .systemPower, .batteryPower:
            return normalizedThresholdLevels(primary, primary + 10, primary + 20)
        case .batteryPercentage:
            return normalizedThresholdLevels(primary, primary - 5, primary - 10)
        case .thermalState:
            return normalizedThresholdLevels(primary, 2, 3)
        }
    }

    fileprivate func normalizedThresholdLevels(
        _ level1: Double,
        _ level2: Double,
        _ level3: Double
    ) -> ThresholdLevelValues {
        let recommended = recommendedRawLevels(primary: level1)
        let first = level1.isFinite ? clamped(level1) : clamped(defaultValue)
        let second = level2.isFinite ? clamped(level2) : clamped(recommended.1)
        let third = level3.isFinite ? clamped(level3) : clamped(recommended.2)
        switch direction {
        case .above:
            let orderedSecond = max(first, second)
            return ThresholdLevelValues(
                level1: first,
                level2: orderedSecond,
                level3: max(orderedSecond, third)
            )
        case .below:
            let orderedSecond = min(first, second)
            return ThresholdLevelValues(
                level1: first,
                level2: orderedSecond,
                level3: min(orderedSecond, third)
            )
        }
    }

    private func recommendedRawLevels(primary: Double) -> (Double, Double, Double) {
        let primary = primary.isFinite ? primary : defaultValue
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage,
             .temperatureCPU, .temperatureGPU, .temperatureMemory, .temperatureStorage,
             .temperatureBattery, .temperatureAirflow, .temperatureWireless,
             .temperaturePowerManagement:
            return (primary, primary + 5, primary + 10)
        case .networkDownload, .networkUpload, .diskRead, .diskWrite:
            return (primary, primary * 1.5, primary * 2)
        case .fanSpeed:
            return (primary, primary + 500, primary + 1_000)
        case .systemPower, .batteryPower:
            return (primary, primary + 10, primary + 20)
        case .batteryPercentage:
            return (primary, primary - 5, primary - 10)
        case .thermalState:
            return (primary, 2, 3)
        }
    }

    func measurement(from snapshot: PerformanceSnapshot) -> ThresholdMeasurement? {
        switch self {
        case .cpuUsage:
            return measurement(snapshot.cpu.usage, object: "CPU")
        case .gpuUsage:
            return snapshot.gpu.usage.map { measurement($0, object: "GPU") }
        case .memoryUsage:
            guard snapshot.memory.total > 0 else { return nil }
            let value = Double(snapshot.memory.used) / Double(snapshot.memory.total) * 100
            return measurement(value, object: "内存")
        case .networkDownload:
            return measurement(snapshot.network.download / 1_048_576, object: "下载")
        case .networkUpload:
            return measurement(snapshot.network.upload / 1_048_576, object: "上传")
        case .diskRead:
            return measurement(snapshot.disk.read / 1_048_576, object: "磁盘读取")
        case .diskWrite:
            return measurement(snapshot.disk.write / 1_048_576, object: "磁盘写入")
        case .thermalState:
            let value = thermalValue(snapshot.thermal.state)
            return ThresholdMeasurement(rawValue: value, valueText: thermalText(value), objectLabel: "系统")
        case .batteryPercentage:
            return snapshot.battery.map { measurement($0.percentage, object: "电池") }
        case .temperatureCPU:
            return snapshot.thermal.temperatures.cpu.map { temperature($0.maximumCelsius, object: "CPU") }
        case .temperatureGPU:
            return snapshot.thermal.temperatures.gpu.map { temperature($0.maximumCelsius, object: "GPU") }
        case .temperatureMemory:
            return snapshot.thermal.temperatures.memory.map { temperature($0.maximumCelsius, object: "内存") }
        case .temperatureStorage:
            return snapshot.thermal.temperatures.nandCelsius.map { temperature($0, object: "NAND") }
        case .temperatureBattery:
            return snapshot.thermal.temperatures.battery.map { temperature($0.maximumCelsius, object: "电池") }
        case .temperatureAirflow:
            let temperatures = [
                snapshot.thermal.temperatures.airflowLeftCelsius,
                snapshot.thermal.temperatures.airflowRightCelsius
            ].compactMap { $0 }
            return temperatures.max().map { temperature($0, object: "风道") }
        case .temperatureWireless:
            return snapshot.thermal.temperatures.wirelessCelsius.map { temperature($0, object: "Wi-Fi") }
        case .temperaturePowerManagement:
            return snapshot.thermal.temperatures.powerManagement.map {
                temperature($0.maximumCelsius, object: "电源管理")
            }
        case .fanSpeed:
            guard let fan = snapshot.fans.max(by: { $0.speedRPM < $1.speedRPM }) else { return nil }
            return ThresholdMeasurement(
                rawValue: fan.speedRPM,
                valueText: String(Int(fan.speedRPM.rounded())),
                objectLabel: "风扇 \(fan.id + 1)"
            )
        case .systemPower:
            return snapshot.battery?.systemPowerWatts.map { power($0, object: "整机") }
        case .batteryPower:
            guard let battery = snapshot.battery,
                  let value = battery.batteryPowerWatts ?? battery.estimatedBatteryPowerWatts else { return nil }
            return power(abs(value), object: "电池")
        }
    }

    private func measurement(_ value: Double, object: String) -> ThresholdMeasurement {
        let text: String
        switch self {
        case .cpuUsage, .gpuUsage, .memoryUsage, .batteryPercentage:
            text = "\(Int(value.rounded()))%"
        case .networkDownload, .networkUpload, .diskRead, .diskWrite:
            text = Self.compactRate(value)
        default:
            text = String(Int(value.rounded()))
        }
        return ThresholdMeasurement(rawValue: value, valueText: text, objectLabel: object)
    }

    private func temperature(_ value: Double, object: String) -> ThresholdMeasurement {
        ThresholdMeasurement(
            rawValue: value,
            valueText: "\(Int(value.rounded()))°",
            objectLabel: object
        )
    }

    private func power(_ value: Double, object: String) -> ThresholdMeasurement {
        let precision = abs(value) < 10 ? 1 : 0
        return ThresholdMeasurement(
            rawValue: value,
            valueText: String(format: "%.*fW", precision, value),
            objectLabel: object
        )
    }

    private func thermalValue(_ state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 0
        }
    }

    private func thermalText(_ value: Double) -> String {
        switch Int(value) {
        case 1: "偏热"
        case 2: "较热"
        case 3: "严重"
        default: "正常"
        }
    }

    private static func compactRate(_ megabytesPerSecond: Double) -> String {
        let value = max(0, megabytesPerSecond)
        if value < 1 {
            return "\(Int((value * 1_024).rounded()))K/s"
        }
        if value >= 1_024 {
            let gigabytes = value / 1_024
            return gigabytes < 10
                ? String(format: "%.1fG/s", gigabytes)
                : "\(Int(gigabytes.rounded()))G/s"
        }
        return value < 10
            ? String(format: "%.1fM/s", value)
            : "\(Int(value.rounded()))M/s"
    }
}

struct ThresholdRule: Codable, Equatable, Identifiable {
    let kind: ThresholdMetric
    var isEnabled: Bool
    var value: Double
    var level2Value: Double
    var level3Value: Double

    var id: ThresholdMetric { kind }

    init(
        kind: ThresholdMetric,
        isEnabled: Bool,
        value: Double,
        level2Value: Double? = nil,
        level3Value: Double? = nil
    ) {
        let recommended = kind.recommendedThresholdLevels(primary: value)
        let normalized = kind.normalizedThresholdLevels(
            value,
            level2Value ?? recommended.level2,
            level3Value ?? recommended.level3
        )
        self.kind = kind
        self.isEnabled = isEnabled
        self.value = normalized.level1
        self.level2Value = normalized.level2
        self.level3Value = normalized.level3
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ThresholdMetric.self, forKey: .kind)
        let value = try container.decode(Double.self, forKey: .value)
        self.init(
            kind: kind,
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            value: value,
            level2Value: try container.decodeIfPresent(Double.self, forKey: .level2Value),
            level3Value: try container.decodeIfPresent(Double.self, forKey: .level3Value)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(value, forKey: .value)
        try container.encode(level2Value, forKey: .level2Value)
        try container.encode(level3Value, forKey: .level3Value)
    }

    func severity(forActiveValue value: Double) -> ThresholdSeverity {
        if kind == .thermalState {
            if value >= 3 { return .level3 }
            if value >= 2 { return .level2 }
            return .level1
        }
        switch kind.direction {
        case .above:
            if value >= level3Value { return .level3 }
            if value >= level2Value { return .level2 }
            return .level1
        case .below:
            if value <= level3Value { return .level3 }
            if value <= level2Value { return .level2 }
            return .level1
        }
    }

    static func defaultRule(for kind: ThresholdMetric) -> ThresholdRule {
        ThresholdRule(kind: kind, isEnabled: false, value: kind.defaultValue)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case isEnabled
        case value
        case level2Value
        case level3Value
    }
}

struct ThresholdMeasurement: Equatable {
    let rawValue: Double
    let valueText: String
    let objectLabel: String
}

struct ThresholdAlert: Identifiable, Equatable {
    let kind: ThresholdMetric
    let measurement: ThresholdMeasurement
    let thresholdValue: Double
    let severity: ThresholdSeverity
    let activatedAt: Date

    var id: ThresholdMetric { kind }
}

enum ThresholdTransition: Equatable {
    case unchanged
    case activated
    case recovered
}

struct ThresholdTriggerState {
    private(set) var triggerCount = 0
    private(set) var recoveryCount = 0
    private(set) var isActive = false
    private(set) var latestMeasurement: ThresholdMeasurement?
    private(set) var latestSeverity: ThresholdSeverity?
    private(set) var activatedAt: Date?

    mutating func update(
        kind: ThresholdMetric,
        rule: ThresholdRule,
        measurement: ThresholdMeasurement,
        at date: Date = Date()
    ) -> ThresholdTransition {
        latestMeasurement = measurement

        if isActive {
            latestSeverity = rule.severity(forActiveValue: measurement.rawValue)
            if kind.isRecovered(value: measurement.rawValue, threshold: rule.value) {
                recoveryCount += 1
                if recoveryCount >= 3 {
                    isActive = false
                    triggerCount = 0
                    recoveryCount = 0
                    activatedAt = nil
                    latestSeverity = nil
                    return .recovered
                }
            } else {
                recoveryCount = 0
            }
            return .unchanged
        }

        if kind.isTriggered(value: measurement.rawValue, threshold: rule.value) {
            triggerCount += 1
            if triggerCount >= 2 {
                isActive = true
                triggerCount = 0
                recoveryCount = 0
                activatedAt = date
                latestSeverity = rule.severity(forActiveValue: measurement.rawValue)
                return .activated
            }
        } else {
            triggerCount = 0
        }
        return .unchanged
    }
}

struct ThresholdEvaluation {
    let kind: ThresholdMetric
    let rule: ThresholdRule
    let measurement: ThresholdMeasurement
}

struct ThresholdAlertStateChange {
    let kind: ThresholdMetric
    let transition: ThresholdTransition
    let measurement: ThresholdMeasurement
    let thresholdValue: Double
}

struct ThresholdAlertPresentationUpdate {
    let changes: [ThresholdAlertStateChange]
    let membershipChanged: Bool
}

struct ThresholdAlertPresentationState {
    private var triggerStates: [ThresholdMetric: ThresholdTriggerState] = [:]
    private var alertOrder: [ThresholdMetric] = []
    private(set) var alertRotationIndex = 0

    func isActive(_ kind: ThresholdMetric) -> Bool {
        triggerStates[kind]?.isActive == true
    }

    mutating func update(
        _ evaluations: [ThresholdEvaluation],
        at date: Date = Date()
    ) -> ThresholdAlertPresentationUpdate {
        var changes: [ThresholdAlertStateChange] = []
        var activatedKinds: [ThresholdMetric] = []

        for evaluation in evaluations {
            var state = triggerStates[evaluation.kind] ?? ThresholdTriggerState()
            let transition = state.update(
                kind: evaluation.kind,
                rule: evaluation.rule,
                measurement: evaluation.measurement,
                at: date
            )
            triggerStates[evaluation.kind] = state

            switch transition {
            case .activated:
                activatedKinds.append(evaluation.kind)
            case .recovered:
                alertOrder.removeAll { $0 == evaluation.kind }
            case .unchanged:
                continue
            }
            changes.append(
                ThresholdAlertStateChange(
                    kind: evaluation.kind,
                    transition: transition,
                    measurement: evaluation.measurement,
                    thresholdValue: evaluation.rule.value
                )
            )
        }

        for kind in activatedKinds.reversed() {
            alertOrder.removeAll { $0 == kind }
            alertOrder.insert(kind, at: 0)
        }
        let membershipChanged = !changes.isEmpty
        if membershipChanged {
            alertRotationIndex = 0
        }
        return ThresholdAlertPresentationUpdate(
            changes: changes,
            membershipChanged: membershipChanged
        )
    }

    mutating func remove(_ kinds: Set<ThresholdMetric>) -> Bool {
        let removedActiveAlert = kinds.contains { triggerStates[$0]?.isActive == true }
        for kind in kinds {
            triggerStates.removeValue(forKey: kind)
            alertOrder.removeAll { $0 == kind }
        }
        if removedActiveAlert {
            alertRotationIndex = 0
        }
        return removedActiveAlert
    }

    func alerts(using rules: [ThresholdMetric: ThresholdRule]) -> [ThresholdAlert] {
        alertOrder.compactMap { kind in
            guard let state = triggerStates[kind], state.isActive,
                  let measurement = state.latestMeasurement,
                  let severity = state.latestSeverity,
                  let activatedAt = state.activatedAt,
                  let rule = rules[kind] else { return nil }
            return ThresholdAlert(
                kind: kind,
                measurement: measurement,
                thresholdValue: rule.value,
                severity: severity,
                activatedAt: activatedAt
            )
        }
    }

    func visibleAlert(using rules: [ThresholdMetric: ThresholdRule]) -> ThresholdAlert? {
        let alerts = alerts(using: rules)
        guard !alerts.isEmpty else { return nil }
        return alerts[min(alertRotationIndex, alerts.count - 1)]
    }

    mutating func advanceRotation(
        using rules: [ThresholdMetric: ThresholdRule]
    ) -> ThresholdAlert? {
        let alerts = alerts(using: rules)
        guard alerts.count > 1 else { return alerts.first }
        alertRotationIndex = (alertRotationIndex + 1) % alerts.count
        return alerts[alertRotationIndex]
    }

    mutating func resetRotation() {
        alertRotationIndex = 0
    }
}
