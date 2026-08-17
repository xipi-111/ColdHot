import Foundation

enum ThresholdDirection {
    case above
    case below
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

    var id: ThresholdMetric { kind }

    static func defaultRule(for kind: ThresholdMetric) -> ThresholdRule {
        ThresholdRule(kind: kind, isEnabled: false, value: kind.defaultValue)
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

    mutating func update(
        kind: ThresholdMetric,
        rule: ThresholdRule,
        measurement: ThresholdMeasurement
    ) -> ThresholdTransition {
        latestMeasurement = measurement

        if isActive {
            if kind.isRecovered(value: measurement.rawValue, threshold: rule.value) {
                recoveryCount += 1
                if recoveryCount >= 3 {
                    isActive = false
                    triggerCount = 0
                    recoveryCount = 0
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
                return .activated
            }
        } else {
            triggerCount = 0
        }
        return .unchanged
    }
}
