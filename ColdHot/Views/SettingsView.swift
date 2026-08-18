import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var panelBackgroundStore: PanelBackgroundStore
    @ObservedObject var monitor: PerformanceMonitor
    @ObservedObject var updateController: UpdateController
    @State private var selectedPage: SettingsPage = .appearance
    @State private var expandedMetrics: Set<MetricKind> = []
    @State private var expandedThresholdMetrics: Set<MetricKind> = []
    @State private var showsPrivacyPolicy = false
    @State private var isChoosingBackground = false
    @State private var backgroundErrorMessage: String?
    @State private var notificationAuthorizationDenied = false

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 208, max: 250)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedPage.rawValue)
                        .font(.system(size: 30, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 16)

                selectedSettingsPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.green)
        .frame(minWidth: 1_040, minHeight: 760)
        .background(SettingsWindowConfigurator())
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .fileImporter(
            isPresented: $isChoosingBackground,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleBackgroundSelection
        )
        .alert(
            "无法设置背景图片",
            isPresented: Binding(
                get: { backgroundErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { backgroundErrorMessage = nil }
                }
            )
        ) {
            Button("好", role: .cancel) { backgroundErrorMessage = nil }
        } message: {
            Text(backgroundErrorMessage ?? "请稍后重试。")
        }
        .alert("无法开启通知", isPresented: $notificationAuthorizationDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在系统设置的通知页面允许 ColdHot 发送通知。")
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding<SettingsPage?>(
                get: { selectedPage },
                set: { selection in
                    if let selection { selectedPage = selection }
                }
            )) {
                Section("设置") {
                    ForEach(SettingsPage.allCases) { page in
                        Label(page.rawValue, systemImage: page.symbol)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("ColdHot")
                        .font(.caption.weight(.medium))
                    Text(currentVersionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var selectedSettingsPage: some View {
        switch selectedPage {
        case .appearance:
            appearancePage
        case .metrics:
            metricsPage
        case .alerts:
            alertsPage
        case .general:
            generalPage
        case .about:
            aboutPage
        }
    }

    private var appearancePage: some View {
        HStack(spacing: 0) {
            Form {
                Section {
                    panelBackgroundSettings
                } header: {
                    Text("面板背景与可读性")
                } footer: {
                    Text("图片会压缩后保存在本机，不会上传，也不会在指标刷新时重复读取。")
                }

                if hasLowReadability {
                    Section {
                        Label("当前组合可能使文字或进度条难以辨认。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("恢复推荐可读性") {
                            settings.restoreRecommendedReadability()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 390)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("菜单面板真实范围")
                    .font(.headline)
                PanelAppearancePreview(
                    image: panelBackgroundStore.image,
                    isBackgroundEnabled: settings.isPanelBackgroundEnabled,
                    dimOpacity: settings.panelBackgroundDimOpacity,
                    cardOpacity: settings.panelCardOpacity,
                    primaryTextOpacity: settings.panelPrimaryTextOpacity,
                    secondaryTextOpacity: settings.panelSecondaryTextOpacity,
                    progressOpacity: settings.panelProgressOpacity,
                    enabledMetrics: previewEnabledMetrics,
                    showsDockQuickControl: settings.showDockQuickControl
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 1)
                }
                Text("使用与菜单面板相同的 370px 画布、卡片高度和图片裁切。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 390, alignment: .topLeading)
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var metricsPage: some View {
        Form {
            Section("快速预设") {
                ForEach(MonitoringPreset.allCases) { preset in
                    Button {
                        settings.applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.rawValue)
                            Spacer()
                            Text(preset.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(MetricCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.rawValue)
                            .font(.headline)
                            .padding(.top, 5)
                        ForEach(MetricKind.allCases.filter {
                            $0.category == category && BuildVariant.availableMetrics.contains($0)
                        }) { metric in
                            metricSetting(metric)
                        }
                    }
                }
            } header: {
                Text("菜单栏指标")
            } footer: {
                Text("一级开关控制整张卡片；详细项目只在卡片展开后按需采样。")
            }
        }
        .formStyle(.grouped)
    }

    private var alertsPage: some View {
        Form {
            Section("系统通知") {
                Toggle("达到阈值时通知", isOn: thresholdNotificationsBinding)
                Toggle(
                    "恢复正常时通知",
                    isOn: $settings.thresholdRecoveryNotificationsEnabled
                )
                .disabled(!settings.thresholdNotificationsEnabled)
                Text("默认关闭。相同指标触发通知后会等待 10 分钟，避免反复打扰。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(thresholdParentMetrics) { metric in
                    thresholdGroup(metric)
                }
            } header: {
                Text("菜单栏阈值显示")
            } footer: {
                Text("连续 2 次达到阈值后显示；连续 3 次回落后恢复。多个告警每 5 秒轮换。")
            }
        }
        .formStyle(.grouped)
    }

    private var generalPage: some View {
        Form {
            if BuildVariant.channel == .direct {
                Section("自动更新") {
                    Toggle(
                        "自动检查更新",
                        isOn: Binding(
                            get: { updateController.automaticallyChecksForUpdates },
                            set: { updateController.automaticallyChecksForUpdates = $0 }
                        )
                    )
                    Toggle(
                        "自动下载更新",
                        isOn: Binding(
                            get: { updateController.automaticallyDownloadsUpdates },
                            set: { updateController.automaticallyDownloadsUpdates = $0 }
                        )
                    )
                    .disabled(!updateController.automaticallyChecksForUpdates)
                    Button("立即检查更新…") { updateController.checkForUpdates() }
                }
            }

            if BuildVariant.supportsDockControl {
                Section("快捷控制") {
                    Toggle("在菜单面板显示“Dock 即时弹出”", isOn: $settings.showDockQuickControl)
                    Text("只影响自动隐藏 Dock 的边缘触发等待时间；关闭时恢复修改前的延迟。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("采样") {
                Picker("刷新间隔", selection: $settings.sampleInterval) {
                    Text("1 秒（实时）").tag(1.0)
                    Text("2 秒（推荐）").tag(2.0)
                    Text("5 秒（省电）").tag(5.0)
                }
                .pickerStyle(.segmented)
                Text("收起时只采集摘要；每核心、进程排行和传感器详情仅按需更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(BuildVariant.settingsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认") { settings.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutPage: some View {
        Form {
            Section("版本") {
                LabeledContent("发行渠道", value: BuildVariant.displayName)
                LabeledContent("当前版本", value: currentVersionText)
                if BuildVariant.channel == .direct {
                    Button("检查更新…") { updateController.checkForUpdates() }
                }
                Button("隐私政策") { showsPrivacyPolicy = true }
            }

            Section("设备能力") {
                capabilityRow("GPU 实时读数", available: monitor.snapshot.gpu.usage != nil)
                capabilityRow("风扇转速", available: !monitor.snapshot.fans.isEmpty)
                capabilityRow("温度传感器", available: hasTemperatureReading)
                capabilityRow(
                    "系统功率",
                    available: monitor.snapshot.battery?.systemPowerWatts != nil
                )
                Button("重新检测") { monitor.probeCapabilities() }
            }

            Section("ColdHot 运行影响") {
                LabeledContent(
                    "CPU",
                    value: monitor.selfResourceSnapshot.cpuUsage.formatted(
                        .number.precision(.fractionLength(1))
                    ) + "%"
                )
                LabeledContent("内存", value: selfMemoryText)
                LabeledContent(
                    "唤醒",
                    value: monitor.selfResourceSnapshot.wakeupsPerSecond.formatted(
                        .number.precision(.fractionLength(1))
                    ) + " 次/秒"
                )
                Text("该区域每约 5 秒更新，用于确认监控工具自身的资源开销。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { monitor.probeCapabilities() }
    }

    @ViewBuilder
    private var panelBackgroundSettings: some View {
        if panelBackgroundStore.image != nil {
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Text("自定义图片")
                    .font(.headline)
                Spacer()
                Button("更换图片…") { isChoosingBackground = true }
            }

            Toggle(
                "使用自定义背景",
                isOn: panelBackgroundEnabledBinding
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("深色遮罩")
                    Spacer()
                    Text("\(Int((settings.panelBackgroundDimOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: panelBackgroundDimOpacityBinding,
                    in: 0...0.70,
                    step: 0.05
                )
                .accessibilityLabel("深色遮罩强度")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("卡片不透明度")
                    Spacer()
                    Text("\(Int((settings.panelCardOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: panelCardOpacityBinding,
                    in: 0.10...1,
                    step: 0.05
                )
                .accessibilityLabel("卡片不透明度")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("主文字亮度")
                    Spacer()
                    Text("\(Int((settings.panelPrimaryTextOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: panelPrimaryTextOpacityBinding,
                    in: 0.50...1,
                    step: 0.05
                )
                .accessibilityLabel("面板主文字亮度")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("辅助文字亮度")
                    Spacer()
                    Text("\(Int((settings.panelSecondaryTextOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: panelSecondaryTextOpacityBinding,
                    in: 0.50...1,
                    step: 0.05
                )
                .accessibilityLabel("面板辅助文字亮度")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("进度条透明度")
                    Spacer()
                    Text("\(Int((settings.panelProgressOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: panelProgressOpacityBinding,
                    in: 0.50...1,
                    step: 0.05
                )
                .accessibilityLabel("面板进度条透明度")
            }

            HStack {
                Spacer()
                Button("移除背景", role: .destructive) {
                    removeBackgroundImage()
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 3) {
                    Text("使用自己的图片")
                        .font(.headline)
                    Text("支持系统可读取的 PNG、JPEG、HEIC 和 TIFF 图片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("选择图片…") { isChoosingBackground = true }
            }
        }
    }

    private var panelBackgroundEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isPanelBackgroundEnabled },
            set: { enabled in
                settings.setPanelBackgroundEnabled(
                    enabled && panelBackgroundStore.hasImage
                )
            }
        )
    }

    private var thresholdNotificationsBinding: Binding<Bool> {
        Binding(
            get: { settings.thresholdNotificationsEnabled },
            set: { enabled in
                guard enabled else {
                    settings.thresholdNotificationsEnabled = false
                    return
                }
                ThresholdNotificationController.requestAuthorization { granted in
                    DispatchQueue.main.async {
                        settings.thresholdNotificationsEnabled = granted
                        notificationAuthorizationDenied = !granted
                    }
                }
            }
        )
    }

    private var panelBackgroundDimOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.panelBackgroundDimOpacity },
            set: settings.setPanelBackgroundDimOpacity
        )
    }

    private var panelCardOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.panelCardOpacity },
            set: settings.setPanelCardOpacity
        )
    }

    private var panelPrimaryTextOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.panelPrimaryTextOpacity },
            set: settings.setPanelPrimaryTextOpacity
        )
    }

    private var panelSecondaryTextOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.panelSecondaryTextOpacity },
            set: settings.setPanelSecondaryTextOpacity
        )
    }

    private var panelProgressOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.panelProgressOpacity },
            set: settings.setPanelProgressOpacity
        )
    }

    private var previewEnabledMetrics: [MetricKind] {
        MetricKind.allCases.filter {
            BuildVariant.availableMetrics.contains($0) && settings.isEnabled($0)
        }
    }

    private var hasLowReadability: Bool {
        guard settings.isPanelBackgroundEnabled && panelBackgroundStore.hasImage else {
            return false
        }
        return settings.panelCardOpacity < 0.35
            || settings.panelPrimaryTextOpacity < 0.70
            || settings.panelSecondaryTextOpacity < 0.65
            || settings.panelProgressOpacity < 0.65
    }

    private var hasTemperatureReading: Bool {
        let temperatures = monitor.snapshot.thermal.temperatures
        return temperatures.cpu != nil
            || temperatures.gpu != nil
            || temperatures.memory != nil
            || temperatures.nandCelsius != nil
            || temperatures.battery != nil
            || temperatures.airflowLeftCelsius != nil
            || temperatures.airflowRightCelsius != nil
            || temperatures.wirelessCelsius != nil
            || temperatures.powerManagement != nil
    }

    private var selfMemoryText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: monitor.selfResourceSnapshot.memoryBytes),
            countStyle: .memory
        )
    }

    private var currentVersionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version)（\(build)）"
    }

    private func capabilityRow(_ title: String, available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(
                available ? "本机可用" : "本机未返回",
                systemImage: available ? "checkmark.circle.fill" : "minus.circle"
            )
            .font(.caption)
            .foregroundStyle(available ? Color.green : Color.secondary)
        }
    }

    private func handleBackgroundSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try panelBackgroundStore.importImage(from: url)
                settings.setPanelBackgroundEnabled(true)
            } catch {
                backgroundErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            let cocoaError = error as NSError
            guard cocoaError.domain != NSCocoaErrorDomain
                    || cocoaError.code != NSUserCancelledError else {
                return
            }
            backgroundErrorMessage = error.localizedDescription
        }
    }

    private func removeBackgroundImage() {
        settings.setPanelBackgroundEnabled(false)
        do {
            try panelBackgroundStore.removeImage()
        } catch {
            backgroundErrorMessage = error.localizedDescription
        }
    }

    private func metricSetting(_ metric: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(metric.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                    Text(metric.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: metricBinding(metric))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("显示 \(metric.title)")
            }

            DisclosureGroup(isExpanded: disclosureBinding(metric)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(metric.details) { detail in
                        Toggle(isOn: detailBinding(detail)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.title)
                                    .font(.system(size: 12))
                                Text(detail.explanation)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel(detail.title)
                        .accessibilityHint(detail.explanation)
                    }
                }
                .padding(.leading, 31)
                .padding(.top, 6)
            } label: {
                Text("详细项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.isEnabled(metric))
            .padding(.leading, 32)
        }
        .padding(.vertical, 3)
    }

    private var thresholdParentMetrics: [MetricKind] {
        MetricKind.allCases.filter { metric in
            BuildVariant.availableThresholdMetrics.contains { $0.metric == metric }
        }
    }

    private func thresholdKinds(for metric: MetricKind) -> [ThresholdMetric] {
        ThresholdMetric.allCases.filter {
            $0.metric == metric && BuildVariant.availableThresholdMetrics.contains($0)
        }
    }

    private func thresholdGroup(_ metric: MetricKind) -> some View {
        DisclosureGroup(isExpanded: thresholdDisclosureBinding(metric)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(thresholdKinds(for: metric)) { kind in
                    thresholdSetting(kind)
                }
            }
            .padding(.leading, 30)
            .padding(.top, 8)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(metric.tint)
                    .frame(width: 21)
                Text(metric.title)
                Spacer()
                let enabledCount = thresholdKinds(for: metric).filter {
                    settings.thresholdRule(for: $0).isEnabled
                }.count
                if enabledCount > 0 {
                    Text("已开启 \(enabledCount) 项")
                        .font(.caption2)
                        .foregroundStyle(metric.tint)
                }
            }
        }
        .tint(metric.tint)
    }

    private func thresholdSetting(_ kind: ThresholdMetric) -> some View {
        let rule = settings.thresholdRule(for: kind)
        return HStack(alignment: .center, spacing: 9) {
            Toggle("", isOn: thresholdEnabledBinding(kind))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("启用\(kind.title)阈值")

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 12))
                Text(kind.explanation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 10)

            thresholdEditor(kind)
                .disabled(!rule.isEnabled)
                .opacity(rule.isEnabled ? 1 : 0.45)
        }
    }

    @ViewBuilder
    private func thresholdEditor(_ kind: ThresholdMetric) -> some View {
        if kind == .thermalState {
            Picker("", selection: thresholdValueBinding(kind)) {
                Text("偏热").tag(1.0)
                Text("较热").tag(2.0)
                Text("严重").tag(3.0)
            }
            .labelsHidden()
            .frame(width: 88)
        } else {
            HStack(spacing: 4) {
                TextField(
                    "阈值",
                    value: thresholdValueBinding(kind),
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 68)
                .accessibilityLabel("\(kind.title)阈值")

                Text(kind.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
    }

    private func metricBinding(_ metric: MetricKind) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(metric) },
            set: { settings.setEnabled($0, for: metric) }
        )
    }

    private func detailBinding(_ detail: MetricDetail) -> Binding<Bool> {
        Binding(
            get: { settings.isDetailEnabled(detail) },
            set: { settings.setDetailEnabled($0, for: detail) }
        )
    }

    private func thresholdEnabledBinding(_ kind: ThresholdMetric) -> Binding<Bool> {
        Binding(
            get: { settings.thresholdRule(for: kind).isEnabled },
            set: { settings.setThresholdEnabled($0, for: kind) }
        )
    }

    private func thresholdValueBinding(_ kind: ThresholdMetric) -> Binding<Double> {
        Binding(
            get: { settings.thresholdRule(for: kind).value },
            set: { settings.setThresholdValue($0, for: kind) }
        )
    }

    private func disclosureBinding(_ metric: MetricKind) -> Binding<Bool> {
        Binding(
            get: { expandedMetrics.contains(metric) },
            set: { expanded in
                if expanded {
                    expandedMetrics.insert(metric)
                } else {
                    expandedMetrics.remove(metric)
                }
            }
        )
    }

    private func thresholdDisclosureBinding(_ metric: MetricKind) -> Binding<Bool> {
        Binding(
            get: { expandedThresholdMetrics.contains(metric) },
            set: { expanded in
                if expanded {
                    expandedThresholdMetrics.insert(metric)
                } else {
                    expandedThresholdMetrics.remove(metric)
                }
            }
        )
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowConfigurationView {
        SettingsWindowConfigurationView()
    }

    func updateNSView(_ nsView: SettingsWindowConfigurationView, context: Context) {
        nsView.configureWindow()
    }
}

private final class SettingsWindowConfigurationView: NSView {
    private weak var configuredWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    deinit {
        removeWindowObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.applyConfiguration(to: window)
            self.observeWindowIfNeeded(window)
        }
    }

    private func applyConfiguration(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar?.isVisible = false
    }

    private func observeWindowIfNeeded(_ window: NSWindow) {
        guard configuredWindow !== window else { return }
        removeWindowObservers()
        configuredWindow = window

        let center = NotificationCenter.default
        windowObservers = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResizeNotification
        ].map { name in
            center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window,
                      self.configuredWindow === window else { return }
                self.applyConfiguration(to: window)
            }
        }
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }
}
