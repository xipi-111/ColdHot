import SwiftUI

enum MetricCategory: String, CaseIterable, Identifiable {
    case compute = "计算"
    case resources = "系统资源"
    case connectivity = "连接"
    case power = "电源与温控"

    var id: String { rawValue }
}

enum MetricKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case thermal
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .network: "网络"
        case .thermal: "热状态"
        case .battery: "电池"
        }
    }

    var explanation: String {
        switch self {
        case .cpu: "处理器使用率、负载和高占用进程"
        case .gpu: "Apple GPU 利用率和显示环境"
        case .memory: "物理内存、压力、交换与进程占用"
        case .disk: "存储吞吐、容量、IOPS 和进程读写"
        case .network: "主接口的收发速度与连接质量"
        case .thermal: "系统热压力等级与按需温度传感器"
        case .battery: "电量、健康、循环次数与电气信息"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d.top.filled"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .thermal: "thermometer.medium"
        case .battery: "battery.75percent"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: .blue
        case .gpu: .purple
        case .memory: .orange
        case .disk: .mint
        case .network: .cyan
        case .thermal: .red
        case .battery: .green
        }
    }

    var category: MetricCategory {
        switch self {
        case .cpu, .gpu:
            .compute
        case .memory, .disk:
            .resources
        case .network:
            .connectivity
        case .thermal, .battery:
            .power
        }
    }

    var details: [MetricDetail] {
        MetricDetail.allCases.filter {
            $0.metric == self && BuildVariant.availableDetails.contains($0)
        }
    }
}

enum MetricDetail: String, CaseIterable, Codable, Identifiable, Hashable {
    case cpuBreakdown
    case cpuLoad
    case cpuCores
    case cpuProcesses
    case cpuWakeups
    case gpuBreakdown
    case gpuDisplays
    case memoryComposition
    case memorySwap
    case memoryProcesses
    case diskCapacity
    case diskIOPS
    case diskTotals
    case diskProcesses
    case networkInterface
    case networkPackets
    case networkTotals
    case networkLatency
    case thermalDuration
    case thermalCPU
    case thermalGPU
    case thermalMemory
    case thermalStorage
    case thermalBattery
    case thermalAirflow
    case thermalWireless
    case thermalPMU
    case batteryRemaining
    case batteryHealth
    case batteryCycles
    case batteryElectrical
    case batteryLowPower

    var id: String { rawValue }

    var metric: MetricKind {
        switch self {
        case .cpuBreakdown, .cpuLoad, .cpuCores, .cpuProcesses, .cpuWakeups: .cpu
        case .gpuBreakdown, .gpuDisplays: .gpu
        case .memoryComposition, .memorySwap, .memoryProcesses: .memory
        case .diskCapacity, .diskIOPS, .diskTotals, .diskProcesses: .disk
        case .networkInterface, .networkPackets, .networkTotals, .networkLatency: .network
        case .thermalDuration, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage,
             .thermalBattery, .thermalAirflow, .thermalWireless, .thermalPMU: .thermal
        case .batteryRemaining, .batteryHealth, .batteryCycles, .batteryElectrical, .batteryLowPower: .battery
        }
    }

    var title: String {
        switch self {
        case .cpuBreakdown: "用户/系统/空闲"
        case .cpuLoad: "1、5、15 分钟负载"
        case .cpuCores: "每核心使用率"
        case .cpuProcesses: "高 CPU 进程"
        case .cpuWakeups: "高唤醒进程"
        case .gpuBreakdown: "Renderer/Tiler 利用率"
        case .gpuDisplays: "显示器与刷新率"
        case .memoryComposition: "内存构成"
        case .memorySwap: "交换内存"
        case .memoryProcesses: "高内存进程"
        case .diskCapacity: "容量与剩余空间"
        case .diskIOPS: "读写 IOPS"
        case .diskTotals: "累计读写"
        case .diskProcesses: "高磁盘读写进程"
        case .networkInterface: "接口与连接类型"
        case .networkPackets: "数据包、错误和丢包"
        case .networkTotals: "累计流量"
        case .networkLatency: "网络延迟主动测试"
        case .thermalDuration: "状态持续时间"
        case .thermalCPU: "CPU 温度"
        case .thermalGPU: "GPU 温度"
        case .thermalMemory: "内存温度"
        case .thermalStorage: "NAND 温度"
        case .thermalBattery: "电池温度"
        case .thermalAirflow: "左右风道温度"
        case .thermalWireless: "Wi-Fi 温度"
        case .thermalPMU: "电源管理温度"
        case .batteryRemaining: "剩余充电/使用时间"
        case .batteryHealth: "健康与容量"
        case .batteryCycles: "循环次数"
        case .batteryElectrical: "实时功率与电气信息"
        case .batteryLowPower: "低电量模式"
        }
    }

    var explanation: String {
        switch self {
        case .networkLatency:
            "展开网络卡片时连接 1.1.1.1:443，每约 10 秒测试一次"
        case .cpuProcesses, .cpuWakeups, .memoryProcesses, .diskProcesses:
            "仅在对应卡片展开时约每 3 秒更新"
        case .cpuCores:
            "仅在 CPU 卡片展开时采集"
        case .batteryCycles:
            "从 Mac 电池控制器读取当前循环次数"
        case .batteryElectrical:
            "优先读取 SMC 系统、输入和电池功率；不支持时回退到电池侧估算"
        case .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage,
             .thermalBattery, .thermalAirflow, .thermalWireless, .thermalPMU:
            "仅在展开热状态卡片时读取可用的 SMC/HID 传感器"
        default:
            "仅在展开该指标时采集或显示"
        }
    }

    static var defaults: Set<MetricDetail> = Set(allCases.filter {
        guard BuildVariant.availableDetails.contains($0) else { return false }
        switch $0 {
        case .networkLatency, .thermalCPU, .thermalGPU, .thermalMemory, .thermalStorage,
             .thermalBattery, .thermalAirflow, .thermalWireless, .thermalPMU:
            return false
        default:
            return true
        }
    })
}

struct SamplingRequest {
    let enabledMetrics: Set<MetricKind>
    let enabledDetails: Set<MetricDetail>
    let expandedMetric: MetricKind?
    let backgroundMetrics: Set<MetricKind>
    let backgroundDetails: Set<MetricDetail>

    func includes(_ metric: MetricKind) -> Bool {
        enabledMetrics.contains(metric) || backgroundMetrics.contains(metric)
    }

    func includes(_ detail: MetricDetail) -> Bool {
        (expandedMetric == detail.metric && enabledDetails.contains(detail))
            || backgroundDetails.contains(detail)
    }
}
