import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var expandedMetrics: Set<MetricKind> = []
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
        .frame(width: 560, height: 720)
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
}
