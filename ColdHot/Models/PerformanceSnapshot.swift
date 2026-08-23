import Foundation

struct PerformanceSnapshot {
    var timestamp = Date()
    var cpu = CPUSnapshot()
    var gpu = GPUSnapshot()
    var memory = MemorySnapshot()
    var network = NetworkSnapshot()
    var disk = DiskSnapshot()
    var thermal = ThermalSnapshot()
    var fans: [FanSnapshot] = []
    var battery: BatterySnapshot?
    var topCPUProcesses: [ProcessActivity] = []
    var topWakeupProcesses: [ProcessActivity] = []
    var topMemoryProcesses: [ProcessActivity] = []
    var topDiskProcesses: [ProcessActivity] = []

    static let empty = PerformanceSnapshot()

    func merging(
        _ update: PerformanceSnapshot,
        request: SamplingRequest
    ) -> PerformanceSnapshot {
        var merged = self
        merged.timestamp = update.timestamp
        if request.includes(.cpu) {
            merged.cpu = update.cpu
        }
        if request.includes(.gpu) {
            merged.gpu = update.gpu
        }
        if request.includes(.memory) {
            merged.memory = update.memory
        }
        if request.includes(.network) {
            merged.network = update.network
        }
        if request.includes(.disk) {
            merged.disk = update.disk
        }
        if request.includes(.thermal) {
            merged.thermal = update.thermal
        }
        if request.includesFans {
            merged.fans = update.fans
        }
        if request.includes(.battery) {
            merged.battery = update.battery
        }
        if request.includes(.cpuProcesses) {
            merged.topCPUProcesses = update.topCPUProcesses
        }
        if request.includes(.cpuWakeups) {
            merged.topWakeupProcesses = update.topWakeupProcesses
        }
        if request.includes(.memoryProcesses) {
            merged.topMemoryProcesses = update.topMemoryProcesses
        }
        if request.includes(.diskProcesses) {
            merged.topDiskProcesses = update.topDiskProcesses
        }
        return merged
    }
}

struct MetricTrendPoint: Identifiable, Equatable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

struct SelfResourceSnapshot: Equatable {
    var cpuUsage = 0.0
    var memoryBytes: UInt64 = 0
    var wakeupsPerSecond = 0.0
    var timestamp = Date()
}

struct CPUSnapshot {
    var usage = 0.0
    var user = 0.0
    var system = 0.0
    var idle = 100.0
    var perCore: [Double] = []
    var loadAverage = [0.0, 0.0, 0.0]
}

struct GPUSnapshot {
    var usage: Double?
    var renderer: Double?
    var tiler: Double?
    var displays: [DisplaySnapshot] = []
}

struct DisplaySnapshot: Identifiable {
    let id: UInt32
    let name: String
    let width: Int
    let height: Int
    let refreshRate: Double?
}

struct MemorySnapshot {
    var used: UInt64 = 0
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal
}

enum MemoryPressure: String {
    case normal = "正常"
    case warning = "警告"
    case critical = "严重"
}

struct NetworkSnapshot {
    var download = 0.0
    var upload = 0.0
    var interface = "—"
    var interfaceType = "未知"
    var receivedBytes: UInt64 = 0
    var sentBytes: UInt64 = 0
    var receivedPackets: UInt64 = 0
    var sentPackets: UInt64 = 0
    var inputErrors: UInt64 = 0
    var outputErrors: UInt64 = 0
    var drops: UInt64 = 0
    var latencyMilliseconds: Double?
}

struct DiskSnapshot {
    var read = 0.0
    var write = 0.0
    var readIOPS = 0.0
    var writeIOPS = 0.0
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var availableBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
}

struct ThermalSnapshot {
    var state: ProcessInfo.ThermalState = .nominal
    var stateSince = Date()
    var temperatures = ThermalTemperatureSnapshot()
}

struct ThermalTemperatureSnapshot {
    var cpu: TemperatureSummary?
    var gpu: TemperatureSummary?
    var memory: TemperatureSummary?
    var nandCelsius: Double?
    var battery: TemperatureSummary?
    var airflowLeftCelsius: Double?
    var airflowRightCelsius: Double?
    var wirelessCelsius: Double?
    var powerManagement: TemperatureSummary?
}

struct TemperatureSummary {
    let averageCelsius: Double
    let maximumCelsius: Double
    let sensorCount: Int
}

struct FanSnapshot: Identifiable {
    let id: Int
    let speedRPM: Double
}

struct BatterySnapshot {
    var percentage = 0.0
    var isCharging = false
    var isOnACPower = false
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var health: String?
    var maximumCapacityPercent: Double?
    var cycleCount: Int?
    var voltageVolts: Double?
    var amperageAmps: Double?
    var systemPowerWatts: Double?
    var dcInputPowerWatts: Double?
    var batteryPowerWatts: Double?
    var estimatedBatteryPowerWatts: Double?
    var isLowPowerMode = false
}

struct ProcessActivity: Identifiable {
    let pid: pid_t
    let name: String
    var cpuUsage = 0.0
    var memoryBytes: UInt64 = 0
    var wakeupsPerSecond = 0.0
    var diskReadPerSecond = 0.0
    var diskWritePerSecond = 0.0

    var id: pid_t { pid }
}
