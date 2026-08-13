import SwiftUI
import AppKit
import QuartzCore

struct DashboardView: View {
    @ObservedObject var monitor: PerformanceMonitor
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var dockController: DockDelayController

    private let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useTB, .useGB, .useMB, .useKB]
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if settings.enabledMetrics.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(enabledMetricKinds) { metric in
                            card(for: metric)
                        }
                    }
                    .padding(12)
                }
                .frame(height: metricsViewportHeight)
            }

            if BuildVariant.supportsDockControl && settings.showDockQuickControl {
                Divider()
                dockQuickControl
            }

            Divider()
            footer
        }
        .frame(width: 370)
        .background(.regularMaterial)
        .onDisappear {
            monitor.setExpandedMetric(nil)
        }
        .onChange(of: settings.enabledMetrics) { _, metrics in
            if let expandedMetric = monitor.expandedMetric, !metrics.contains(expandedMetric) {
                monitor.setExpandedMetric(nil)
            }
        }
    }

    private var enabledMetricKinds: [MetricKind] {
        MetricKind.allCases.filter {
            BuildVariant.availableMetrics.contains($0) && settings.isEnabled($0)
        }
    }

    private var metricsViewportHeight: CGFloat {
        let collapsed = CGFloat(enabledMetricKinds.count) * 62
        let spacing = CGFloat(max(0, enabledMetricKinds.count - 1)) * 8
        let expansion: CGFloat = monitor.expandedMetric == nil ? 0 : 300
        return min(max(collapsed + spacing + expansion + 24, 96), 500)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(thermalColor.opacity(0.16))
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundStyle(thermalColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("ColdHot").font(.headline)
                Text("更新于 \(monitor.snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle().fill(thermalColor).frame(width: 7, height: 7)
                Text(thermalTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("尚未选择指标").font(.headline)
            Text("在设置中勾选希望显示的性能指标。")
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsLink { Text("打开设置") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var dockQuickControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "dock.rectangle")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dock 即时弹出")
                    .font(.system(size: 12, weight: .medium))
                if let error = dockController.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else if dockController.isInstant {
                    Text("Dock零延迟弹出已开启")
                        .foregroundStyle(.tertiary)
                } else if !dockController.isAutoHideEnabled {
                    Text("Dock 自动隐藏当前已关闭")
                        .foregroundStyle(.tertiary)
                } else {
                    Text("使用系统默认弹出延迟")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
            Spacer()
            if dockController.isApplying {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { dockController.isInstant },
                    set: dockController.setInstant
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Dock 即时弹出")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .onAppear { dockController.refresh() }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Label("设置", systemImage: "gearshape") }
                .buttonStyle(.plain)
            Spacer()
            if BuildVariant.supportsFanReadings {
                fanStatus
                Divider().frame(height: 14)
            }
            Text("每 \(settings.sampleInterval.formatted()) 秒")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Divider().frame(height: 14)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var fanStatus: some View {
        if let fastestFan = monitor.snapshot.fans.max(by: { $0.speedRPM < $1.speedRPM }) {
            HStack(spacing: 4) {
                SpinningFanIcon(rpm: fastestFan.speedRPM)
                Text("\(Int(fastestFan.speedRPM.rounded())) RPM")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(fanHelpText)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "fan.fill")
                Text("— RPM")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .help("未读取到风扇转速")
        }
    }

    private var fanHelpText: String {
        monitor.snapshot.fans
            .sorted { $0.id < $1.id }
            .map { "风扇 \($0.id + 1)：\(Int($0.speedRPM.rounded())) RPM" }
            .joined(separator: "\n")
    }

    @ViewBuilder
    private func card(for metric: MetricKind) -> some View {
        switch metric {
        case .cpu:
            MetricCard(
                metric: metric,
                value: percent(monitor.snapshot.cpu.usage),
                detail: "用户 \(percent(monitor.snapshot.cpu.user)) · 系统 \(percent(monitor.snapshot.cpu.system))",
                progress: monitor.snapshot.cpu.usage / 100,
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { cpuDetails }
        case .gpu:
            MetricCard(
                metric: metric,
                value: monitor.snapshot.gpu.usage.map(percent) ?? "不可用",
                detail: "Apple GPU 设备利用率",
                progress: monitor.snapshot.gpu.usage.map { $0 / 100 },
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { gpuDetails }
        case .memory:
            MetricCard(
                metric: metric,
                value: bytes(monitor.snapshot.memory.used),
                detail: "压力 \(monitor.snapshot.memory.pressure.rawValue) · 共 \(bytes(monitor.snapshot.memory.total))",
                progress: monitor.snapshot.memory.total > 0
                    ? Double(monitor.snapshot.memory.used) / Double(monitor.snapshot.memory.total)
                    : nil,
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { memoryDetails }
        case .disk:
            MetricCard(
                metric: metric,
                value: "读 \(rate(monitor.snapshot.disk.read))",
                detail: "写 \(rate(monitor.snapshot.disk.write))",
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { diskDetails }
        case .network:
            MetricCard(
                metric: metric,
                value: "↓ \(rate(monitor.snapshot.network.download))",
                detail: "↑ \(rate(monitor.snapshot.network.upload)) · \(monitor.snapshot.network.interface)",
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { networkDetails }
        case .thermal:
            MetricCard(
                metric: metric,
                value: thermalTitle,
                detail: "系统热压力（无需管理员权限）",
                isExpanded: monitor.expandedMetric == metric,
                onToggle: { toggle(metric) }
            ) { thermalDetails }
        case .battery:
            if let battery = monitor.snapshot.battery {
                MetricCard(
                    metric: metric,
                    value: percent(battery.percentage),
                    detail: batterySummary(battery),
                    progress: battery.percentage / 100,
                    isExpanded: monitor.expandedMetric == metric,
                    onToggle: { toggle(metric) }
                ) { batteryDetails(battery) }
            } else {
                MetricCard(
                    metric: metric,
                    value: "不可用",
                    detail: "未检测到内置电池",
                    isExpanded: monitor.expandedMetric == metric,
                    onToggle: { toggle(metric) }
                ) { noDetails }
            }
        }
    }

    private func toggle(_ metric: MetricKind) {
        let next = monitor.expandedMetric == metric ? nil : metric
        withAnimation(.easeInOut(duration: 0.16)) {
            monitor.setExpandedMetric(next)
        }
    }

    @ViewBuilder
    private var cpuDetails: some View {
        let snapshot = monitor.snapshot
        if settings.isDetailEnabled(.cpuBreakdown) {
            DetailSection(title: "CPU 构成") {
                DetailValueRow(label: "用户", value: percent(snapshot.cpu.user))
                DetailValueRow(label: "系统", value: percent(snapshot.cpu.system))
                DetailValueRow(label: "空闲", value: percent(snapshot.cpu.idle))
            }
        }
        if settings.isDetailEnabled(.cpuLoad) {
            DetailSection(title: "系统负载") {
                DetailValueRow(label: "1 / 5 / 15 分钟", value: snapshot.cpu.loadAverage.map(decimal).joined(separator: "  ·  "))
            }
        }
        if settings.isDetailEnabled(.cpuCores) {
            DetailSection(title: "每核心使用率") {
                if snapshot.cpu.perCore.isEmpty {
                    samplingPlaceholder
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(Array(snapshot.cpu.perCore.enumerated()), id: \.offset) { index, usage in
                            HStack(spacing: 5) {
                                Text("C\(index + 1)").font(.system(size: 9)).foregroundStyle(.tertiary)
                                ProgressView(value: usage / 100).controlSize(.mini).tint(.blue)
                                Text(percent(usage)).font(.system(size: 9, design: .rounded)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        if settings.isDetailEnabled(.cpuProcesses) {
            ProcessActivityList(title: "高 CPU 进程", processes: snapshot.topCPUProcesses) { percent($0.cpuUsage) }
        }
        if settings.isDetailEnabled(.cpuWakeups) {
            ProcessActivityList(title: "高唤醒进程", processes: snapshot.topWakeupProcesses) {
                decimal($0.wakeupsPerSecond) + " 次/s"
            }
        }
        if !hasEnabledDetail(for: .cpu) { noDetails }
    }

    @ViewBuilder
    private var gpuDetails: some View {
        let gpu = monitor.snapshot.gpu
        if settings.isDetailEnabled(.gpuBreakdown) {
            DetailSection(title: "GPU 构成") {
                DetailValueRow(label: "Renderer", value: gpu.renderer.map(percent) ?? "不可用")
                DetailValueRow(label: "Tiler", value: gpu.tiler.map(percent) ?? "不可用")
            }
        }
        if settings.isDetailEnabled(.gpuDisplays) {
            DetailSection(title: "显示环境") {
                if gpu.displays.isEmpty {
                    samplingPlaceholder
                } else {
                    ForEach(gpu.displays) { display in
                        DetailValueRow(
                            label: display.name,
                            value: "\(display.width) × \(display.height)" + (display.refreshRate.map { " @ \(decimal($0))Hz" } ?? "")
                        )
                    }
                }
            }
        }
        if !hasEnabledDetail(for: .gpu) { noDetails }
    }

    @ViewBuilder
    private var memoryDetails: some View {
        let memory = monitor.snapshot.memory
        if settings.isDetailEnabled(.memoryComposition) {
            DetailSection(title: "内存构成") {
                DetailValueRow(label: "App/匿名", value: bytes(memory.app))
                DetailValueRow(label: "联动内存", value: bytes(memory.wired))
                DetailValueRow(label: "已压缩", value: bytes(memory.compressed))
                DetailValueRow(label: "文件缓存", value: bytes(memory.cached))
            }
        }
        if settings.isDetailEnabled(.memorySwap) {
            DetailSection(title: "交换内存") {
                DetailValueRow(label: "已使用", value: bytes(memory.swapUsed))
                DetailValueRow(label: "总计", value: bytes(memory.swapTotal))
            }
        }
        if settings.isDetailEnabled(.memoryProcesses) {
            ProcessActivityList(title: "高内存进程", processes: monitor.snapshot.topMemoryProcesses) {
                bytes($0.memoryBytes)
            }
        }
        if !hasEnabledDetail(for: .memory) { noDetails }
    }

    @ViewBuilder
    private var diskDetails: some View {
        let disk = monitor.snapshot.disk
        if settings.isDetailEnabled(.diskCapacity) {
            DetailSection(title: "存储容量") {
                DetailValueRow(label: "可用", value: bytes(disk.availableBytes))
                DetailValueRow(label: "总计", value: bytes(disk.totalBytes))
            }
        }
        if settings.isDetailEnabled(.diskIOPS) {
            DetailSection(title: "实时 IOPS") {
                DetailValueRow(label: "读取", value: decimal(disk.readIOPS) + " 次/s")
                DetailValueRow(label: "写入", value: decimal(disk.writeIOPS) + " 次/s")
            }
        }
        if settings.isDetailEnabled(.diskTotals) {
            DetailSection(title: "启动以来累计") {
                DetailValueRow(label: "读取", value: bytes(disk.bytesRead))
                DetailValueRow(label: "写入", value: bytes(disk.bytesWritten))
            }
        }
        if settings.isDetailEnabled(.diskProcesses) {
            ProcessActivityList(title: "高磁盘读写进程", processes: monitor.snapshot.topDiskProcesses) {
                "↓ \(rate($0.diskReadPerSecond))  ↑ \(rate($0.diskWritePerSecond))"
            }
        }
        if !hasEnabledDetail(for: .disk) { noDetails }
    }

    @ViewBuilder
    private var networkDetails: some View {
        let network = monitor.snapshot.network
        if settings.isDetailEnabled(.networkInterface) {
            DetailSection(title: "当前连接") {
                DetailValueRow(label: "接口", value: network.interface)
                DetailValueRow(label: "类型", value: network.interfaceType)
            }
        }
        if settings.isDetailEnabled(.networkPackets) {
            DetailSection(title: "数据包") {
                DetailValueRow(label: "接收/发送", value: "\(network.receivedPackets) / \(network.sentPackets)")
                DetailValueRow(label: "错误/丢包", value: "\(network.inputErrors + network.outputErrors) / \(network.drops)")
            }
        }
        if settings.isDetailEnabled(.networkTotals) {
            DetailSection(title: "累计流量") {
                DetailValueRow(label: "下载", value: bytes(network.receivedBytes))
                DetailValueRow(label: "上传", value: bytes(network.sentBytes))
            }
        }
        if settings.isDetailEnabled(.networkLatency) {
            DetailSection(title: "网络延迟 · 1.1.1.1:443") {
                DetailValueRow(
                    label: "TCP 建连",
                    value: network.latencyMilliseconds.map { decimal($0) + " ms" } ?? "测试中…"
                )
            }
        }
        if !hasEnabledDetail(for: .network) { noDetails }
    }

    @ViewBuilder
    private var thermalDetails: some View {
        let temperatures = monitor.snapshot.thermal.temperatures
        if settings.isDetailEnabled(.thermalDuration) {
            DetailSection(title: "热状态") {
                DetailValueRow(label: "当前等级", value: thermalTitle, tint: thermalColor)
                DetailValueRow(label: "已持续", value: duration(since: monitor.snapshot.thermal.stateSince))
            }
        }
        if settings.isDetailEnabled(.thermalCPU) {
            DetailSection(title: "CPU 温度") {
                temperatureSummaryRows(temperatures.cpu)
                Text("汇总本机可用且通过有效性检查的 CPU 传感器。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        if settings.isDetailEnabled(.thermalGPU) {
            DetailSection(title: "GPU 温度") {
                temperatureSummaryRows(temperatures.gpu)
            }
        }
        if settings.isDetailEnabled(.thermalMemory) {
            DetailSection(title: "内存温度") {
                temperatureSummaryRows(temperatures.memory)
            }
        }
        if settings.isDetailEnabled(.thermalStorage) {
            DetailSection(title: "存储温度") {
                DetailValueRow(label: "NAND", value: celsius(temperatures.nandCelsius))
            }
        }
        if settings.isDetailEnabled(.thermalBattery) {
            DetailSection(title: "电池温度") {
                temperatureSummaryRows(temperatures.battery)
            }
        }
        if settings.isDetailEnabled(.thermalAirflow) {
            DetailSection(title: "风道温度") {
                DetailValueRow(label: "左侧", value: celsius(temperatures.airflowLeftCelsius))
                DetailValueRow(label: "右侧", value: celsius(temperatures.airflowRightCelsius))
            }
        }
        if settings.isDetailEnabled(.thermalWireless) {
            DetailSection(title: "无线模块温度") {
                DetailValueRow(label: "Wi-Fi", value: celsius(temperatures.wirelessCelsius))
            }
        }
        if settings.isDetailEnabled(.thermalPMU) {
            DetailSection(title: "电源管理温度") {
                temperatureSummaryRows(temperatures.powerManagement)
            }
        }
        if !hasEnabledDetail(for: .thermal) { noDetails }
    }

    @ViewBuilder
    private func temperatureSummaryRows(_ summary: TemperatureSummary?) -> some View {
        if let summary {
            DetailValueRow(label: "平均", value: celsius(summary.averageCelsius))
            DetailValueRow(label: "最高", value: celsius(summary.maximumCelsius))
            DetailValueRow(label: "有效传感器", value: "\(summary.sensorCount) 个")
        } else {
            Text("此机型未返回有效温度")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func batteryDetails(_ battery: BatterySnapshot) -> some View {
        if settings.isDetailEnabled(.batteryRemaining) {
            DetailSection(title: "剩余时间") {
                if battery.isCharging {
                    DetailValueRow(label: "充满预计", value: minutes(battery.timeToFullMinutes))
                } else if battery.isOnACPower {
                    DetailValueRow(label: "电源", value: "已连接，未充电")
                } else {
                    DetailValueRow(label: "可用预计", value: minutes(battery.timeToEmptyMinutes))
                }
            }
        }
        if settings.isDetailEnabled(.batteryHealth) {
            DetailSection(title: "电池健康") {
                DetailValueRow(label: "状态", value: batteryHealth(battery.health))
                DetailValueRow(
                    label: "最大容量",
                    value: battery.maximumCapacityPercent.map(percent) ?? "不可用"
                )
            }
        }
        if settings.isDetailEnabled(.batteryCycles) {
            DetailSection(title: "循环") {
                DetailValueRow(label: "循环次数", value: battery.cycleCount.map { "\($0) 次" } ?? "不可用")
            }
        }
        if settings.isDetailEnabled(.batteryElectrical) {
            DetailSection(title: "实时功率") {
                DetailValueRow(
                    label: "系统总功率",
                    value: battery.systemPowerWatts.map(watts) ?? "传感器不可用"
                )
                DetailValueRow(
                    label: "直流输入",
                    value: battery.dcInputPowerWatts.map(watts) ?? "传感器不可用"
                )
                DetailValueRow(
                    label: "电池充放电",
                    value: battery.batteryPowerWatts.map(watts)
                        ?? battery.estimatedBatteryPowerWatts.map { watts($0) + "（估算）" }
                        ?? "不可用"
                )
                Text(
                    battery.systemPowerWatts != nil || battery.dcInputPowerWatts != nil
                        ? "来自本机 SMC 实时传感器，仅代表 Mac 内部功率。"
                        : "此机型未公开整机功率传感器，当前仅能计算电池侧功率。"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            DetailSection(title: "电气信息") {
                DetailValueRow(label: "电压", value: battery.voltageVolts.map { decimal($0) + " V" } ?? "不可用")
                DetailValueRow(label: "电流", value: battery.amperageAmps.map { decimal($0) + " A" } ?? "不可用")
            }
        }
        if settings.isDetailEnabled(.batteryLowPower) {
            DetailSection(title: "电源模式") {
                DetailValueRow(label: "低电量模式", value: battery.isLowPowerMode ? "已开启" : "已关闭")
            }
        }
        if !hasEnabledDetail(for: .battery) { noDetails }
    }

    private var noDetails: some View {
        Text("未选择详细项目，可在设置中启用。")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var samplingPlaceholder: some View {
        Text("正在采样…")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func hasEnabledDetail(for metric: MetricKind) -> Bool {
        metric.details.contains(where: settings.isDetailEnabled)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func watts(_ value: Double) -> String {
        let precision = abs(value) < 10 ? 2 : 1
        return value.formatted(.number.precision(.fractionLength(precision))) + " W"
    }

    private func celsius(_ value: Double?) -> String {
        value.map(celsius) ?? "传感器不可用"
    }

    private func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private func bytes(_ value: UInt64) -> String {
        bytesFormatter.string(fromByteCount: Int64(clamping: value))
    }

    private func rate(_ value: Double) -> String {
        let value = max(0, value)
        if value < 1_024 {
            return "\(Int(value.rounded())) B/s"
        }
        if value < 1_048_576 {
            return decimal(value / 1_024) + " KB/s"
        }
        if value < 1_073_741_824 {
            return decimal(value / 1_048_576) + " MB/s"
        }
        return decimal(value / 1_073_741_824) + " GB/s"
    }

    private func minutes(_ value: Int?) -> String {
        guard let value else { return "正在估算" }
        return value >= 60 ? "\(value / 60) 小时 \(value % 60) 分" : "\(value) 分钟"
    }

    private func duration(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds >= 3600 { return "\(seconds / 3600) 小时 \((seconds % 3600) / 60) 分" }
        if seconds >= 60 { return "\(seconds / 60) 分钟" }
        return "\(seconds) 秒"
    }

    private func batterySummary(_ battery: BatterySnapshot) -> String {
        if battery.isCharging { return "正在充电" }
        return battery.isOnACPower ? "已连接电源" : "正在使用电池"
    }

    private func batteryHealth(_ value: String?) -> String {
        switch value {
        case "Good": "正常"
        case "Fair": "一般"
        case "Poor": "建议维修"
        case let value?: value
        case nil: "不可用"
        }
    }

    private var thermalTitle: String {
        switch monitor.snapshot.thermal.state {
        case .nominal: "正常"
        case .fair: "偏热"
        case .serious: "较热"
        case .critical: "严重"
        @unknown default: "未知"
        }
    }

    private var thermalColor: Color {
        switch monitor.snapshot.thermal.state {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .secondary
        }
    }
}

private struct SpinningFanIcon: NSViewRepresentable {
    let rpm: Double

    func makeNSView(context: Context) -> FanImageView {
        FanImageView()
    }

    func updateNSView(_ view: FanImageView, context: Context) {
        view.setSpeed(rpm)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FanImageView, context: Context) -> CGSize? {
        CGSize(width: 12, height: 12)
    }
}

private final class FanImageView: NSImageView {
    private var currentRPM = -1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(
            systemSymbolName: "fan.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        imageScaling = .scaleProportionallyUpOrDown
        contentTintColor = .secondaryLabelColor
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSpeed(_ rpm: Double) {
        guard abs(rpm - currentRPM) >= 1 else { return }
        currentRPM = rpm
        layer?.removeAnimation(forKey: "coldhot.fan.rotation")
        guard rpm > 0 else { return }

        let degreesPerSecond = min(max(rpm / 8, 120), 360)
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.byValue = Double.pi * 2
        animation.duration = 360 / degreesPerSecond
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer?.add(animation, forKey: "coldhot.fan.rotation")
    }
}
