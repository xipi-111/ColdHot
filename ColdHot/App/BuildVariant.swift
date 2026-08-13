import Foundation

enum DistributionChannel: String {
    case direct
    case appStore
}

enum BuildVariant {
#if APP_STORE
    static let channel = DistributionChannel.appStore
#else
    static let channel = DistributionChannel.direct
#endif

    static var isAppStore: Bool { channel == .appStore }
    static var displayName: String { isAppStore ? "App Store 版" : "官网版" }

    static var availableMetrics: Set<MetricKind> {
        if isAppStore {
            // macOS 没有公开的整机 GPU 与磁盘实时吞吐 API。App Store
            // 版本不展示依赖未文档化 IORegistry 属性的卡片。
            return [.cpu, .memory, .network, .thermal, .battery]
        }
        return Set(MetricKind.allCases)
    }

    static var availableDetails: Set<MetricDetail> {
        if !isAppStore { return Set(MetricDetail.allCases) }

        return [
            .cpuBreakdown,
            .cpuLoad,
            .cpuCores,
            .memoryComposition,
            .memorySwap,
            .networkInterface,
            .networkPackets,
            .networkTotals,
            .networkLatency,
            .thermalDuration,
            .batteryRemaining,
            .batteryHealth,
            .batteryLowPower
        ]
    }

    static var supportsPrivateSensors: Bool { !isAppStore }
    static var supportsProcessRankings: Bool { !isAppStore }
    static var supportsDockControl: Bool { !isAppStore }
    static var supportsFanReadings: Bool { !isAppStore }

    static var settingsSummary: String {
        if isAppStore {
            return "App Store 版仅使用公开系统接口；温度传感器、风扇、整机功率、进程排行、GPU/磁盘实时统计与 Dock 控制只在官网版提供。"
        }
        return "官网版包含完整的本机传感器、进程排行与 Dock 快捷控制；部分高级读数依赖 macOS 未公开接口。"
    }
}
