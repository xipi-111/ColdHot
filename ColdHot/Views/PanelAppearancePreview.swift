import SwiftUI
import AppKit

struct PanelAppearancePreview: View {
    let image: NSImage?
    let isBackgroundEnabled: Bool
    let dimOpacity: Double
    let backgroundZoom: Double
    let backgroundPosition: CGPoint
    let cardOpacity: Double
    let primaryTextOpacity: Double
    let secondaryTextOpacity: Double
    let progressOpacity: Double
    let enabledMetrics: [MetricKind]
    let showsDockQuickControl: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if enabledMetrics.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(enabledMetrics) { metric in
                            let sample = sampleValue(for: metric)
                            MetricCard(
                                metric: metric,
                                value: sample.value,
                                detail: sample.detail,
                                progress: sample.progress,
                                isExpanded: false,
                                onToggle: {}
                            ) {
                                EmptyView()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(height: PanelLayout.metricsViewportHeight(
                    metricCount: enabledMetrics.count,
                    hasExpandedMetric: false
                ))
                .scrollIndicators(.never)
                .hidePanelVerticalScrollIndicator(allowsScrolling: false)
                .scrollDisabled(true)
            }

            if BuildVariant.supportsDockControl && showsDockQuickControl {
                Divider()
                dockPreview
            }

            Divider()
            footer
        }
        .frame(width: PanelLayout.width)
        .background {
            PanelBackgroundView(
                image: image,
                isEnabled: isBackgroundEnabled,
                dimOpacity: dimOpacity,
                zoom: backgroundZoom,
                position: backgroundPosition
            )
        }
        .panelReadability(
            cardOpacity: cardOpacity,
            primaryTextOpacity: primaryTextOpacity,
            secondaryTextOpacity: secondaryTextOpacity,
            progressOpacity: progressOpacity,
            usesCustomBackground: isBackgroundEnabled && image != nil
        )
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("菜单面板外观预览")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.green.opacity(0.16))
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.green)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("ColdHot")
                    .font(.headline)
                    .panelTextReadability(.primary)
                Text("更新于 12:35:08")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .panelTextReadability(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("热状态 正常")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .panelTextReadability(.secondary)
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("尚未选择指标")
                .font(.headline)
                .panelTextReadability(.primary)
            Text("在设置中勾选希望显示的性能指标。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelTextReadability(.secondary)
            Text("打开设置")
                .panelTextReadability(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.tint, in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var dockPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "dock.rectangle")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dock 即时弹出")
                    .font(.system(size: 12, weight: .medium))
                    .panelTextReadability(.primary)
                Text("Dock零延迟弹出已开启")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .panelTextReadability(.secondary)
            }
            Spacer()
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("设置", systemImage: "gearshape")
                .panelTextReadability(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "fan.fill")
                Text("2,480 RPM")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .panelTextReadability(.secondary)
            Text("每 2 秒")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .panelTextReadability(.secondary)
            Divider().frame(height: 14)
            Text("退出")
                .panelTextReadability(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sampleValue(
        for metric: MetricKind
    ) -> (value: String, detail: String, progress: Double?) {
        switch metric {
        case .cpu:
            ("38.7%", "用户 27.4% · 系统 11.3%", 0.387)
        case .gpu:
            ("24.0%", "Apple GPU 设备利用率", 0.24)
        case .memory:
            ("34.3 GB", "压力正常 · 共 48 GB", 0.715)
        case .disk:
            ("读 2.3 MB/s", "写 594.5 KB/s", nil)
        case .network:
            ("↓ 7.1 KB/s", "↑ 2.9 KB/s · en0", nil)
        case .thermal:
            ("正常", "系统热压力", nil)
        case .battery:
            ("80%", "已连接电源", 0.80)
        }
    }
}
