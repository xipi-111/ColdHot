import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var expandedMetrics: Set<MetricKind> = []
    @State private var expandedThresholdMetrics: Set<MetricKind> = []
    @State private var showsPrivacyPolicy = false

    var body: some View {
        Form {
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
                Text("一级开关控制整张指标卡片；详细项目只会显示在卡片展开区域，并按需启动采样。")
            }

            Section {
                ForEach(thresholdParentMetrics) { metric in
                    thresholdGroup(metric)
                }
            } header: {
                Text("菜单栏阈值显示")
            } footer: {
                Text("连续 2 次达到阈值后，菜单栏会显示实时读数；连续 3 次回落后恢复简易图标。多个告警每 5 秒轮换。传感器阈值会增加少量按需采样。")
            }

            if BuildVariant.supportsDockControl {
                Section("快捷控制") {
                    Toggle("在菜单面板显示“Dock 即时弹出”", isOn: $settings.showDockQuickControl)
                    Text("该快捷开关只影响自动隐藏 Dock 的边缘触发等待时间。切换后 Dock 会短暂重启；关闭时恢复修改前的延迟。")
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

                Text("收起时只采集摘要。每核心和进程排行等详细信息仅在对应卡片展开时更新；网络延迟测试默认关闭。")
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

            Section("关于") {
                LabeledContent("发行渠道", value: BuildVariant.displayName)
                Button("隐私政策") { showsPrivacyPolicy = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .navigationTitle("ColdHot 设置")
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicyView()
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
