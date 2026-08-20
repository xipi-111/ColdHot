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
    private let asset: PanelBackgroundAsset?
    private let playbackController: PanelBackgroundPlaybackController?
    private let playbackIntent: PanelBackgroundPlaybackIntent?

    init(
        asset: PanelBackgroundAsset?,
        controller: PanelBackgroundPlaybackController,
        intent: PanelBackgroundPlaybackIntent,
        dimOpacity: Double,
        backgroundZoom: Double,
        backgroundPosition: CGPoint,
        cardOpacity: Double,
        primaryTextOpacity: Double,
        secondaryTextOpacity: Double,
        progressOpacity: Double,
        enabledMetrics: [MetricKind],
        showsDockQuickControl: Bool
    ) {
        image = asset?.posterImage
        isBackgroundEnabled = intent.isEnabled
        self.dimOpacity = dimOpacity
        self.backgroundZoom = backgroundZoom
        self.backgroundPosition = backgroundPosition
        self.cardOpacity = cardOpacity
        self.primaryTextOpacity = primaryTextOpacity
        self.secondaryTextOpacity = secondaryTextOpacity
        self.progressOpacity = progressOpacity
        self.enabledMetrics = enabledMetrics
        self.showsDockQuickControl = showsDockQuickControl
        self.asset = asset
        playbackController = controller
        playbackIntent = intent
    }

    init(
        image: NSImage?,
        isBackgroundEnabled: Bool,
        dimOpacity: Double,
        backgroundZoom: Double,
        backgroundPosition: CGPoint,
        cardOpacity: Double,
        primaryTextOpacity: Double,
        secondaryTextOpacity: Double,
        progressOpacity: Double,
        enabledMetrics: [MetricKind],
        showsDockQuickControl: Bool
    ) {
        self.image = image
        self.isBackgroundEnabled = isBackgroundEnabled
        self.dimOpacity = dimOpacity
        self.backgroundZoom = backgroundZoom
        self.backgroundPosition = backgroundPosition
        self.cardOpacity = cardOpacity
        self.primaryTextOpacity = primaryTextOpacity
        self.secondaryTextOpacity = secondaryTextOpacity
        self.progressOpacity = progressOpacity
        self.enabledMetrics = enabledMetrics
        self.showsDockQuickControl = showsDockQuickControl
        asset = nil
        playbackController = nil
        playbackIntent = nil
    }

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
            if let playbackController, let playbackIntent {
                PanelBackgroundView(
                    asset: asset,
                    controller: playbackController,
                    intent: playbackIntent,
                    dimOpacity: dimOpacity,
                    zoom: backgroundZoom,
                    position: backgroundPosition
                )
            } else {
                PanelBackgroundView(
                    image: image,
                    isEnabled: isBackgroundEnabled,
                    dimOpacity: dimOpacity,
                    zoom: backgroundZoom,
                    position: backgroundPosition
                )
            }
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

enum PanelBackgroundMenuPolicy {
    static func showsAudioToggle(for asset: PanelBackgroundAsset?) -> Bool {
        asset?.kind == .video && asset?.hasAudio == true
    }

    static func intent(
        asset: PanelBackgroundAsset?,
        isEnabled: Bool,
        isVisible: Bool,
        reduceMotion: Bool,
        audioRequested: Bool
    ) -> PanelBackgroundPlaybackIntent {
        PanelBackgroundPlaybackIntent(
            isEnabled: isEnabled,
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            audioRequested: audioRequested,
            assetIsDynamic: asset?.isDynamic == true,
            assetHasAudio: asset?.hasAudio == true
        )
    }
}

struct PanelBackgroundMenuLifecycle {
    private(set) var isVisible = false

    mutating func didAppear() {
        isVisible = true
    }

    mutating func didDisappear() {
        isVisible = false
    }

    func intent(
        asset: PanelBackgroundAsset?,
        isEnabled: Bool,
        reduceMotion: Bool,
        audioRequested: Bool
    ) -> PanelBackgroundPlaybackIntent {
        PanelBackgroundMenuPolicy.intent(
            asset: asset,
            isEnabled: isEnabled,
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            audioRequested: audioRequested
        )
    }
}

private struct PanelAccessibilityIdentifierReporterKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

private struct PanelAccessibilityLabelReporterKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

private struct PanelAccessibilityActionReporterKey: EnvironmentKey {
    static let defaultValue: ((String, @escaping () -> Void) -> Void)? = nil
}

extension EnvironmentValues {
    var panelAccessibilityIdentifierReporter: ((String) -> Void)? {
        get { self[PanelAccessibilityIdentifierReporterKey.self] }
        set { self[PanelAccessibilityIdentifierReporterKey.self] = newValue }
    }

    var panelAccessibilityLabelReporter: ((String) -> Void)? {
        get { self[PanelAccessibilityLabelReporterKey.self] }
        set { self[PanelAccessibilityLabelReporterKey.self] = newValue }
    }

    var panelAccessibilityActionReporter: (
        (String, @escaping () -> Void) -> Void
    )? {
        get { self[PanelAccessibilityActionReporterKey.self] }
        set { self[PanelAccessibilityActionReporterKey.self] = newValue }
    }
}

struct PanelBackgroundAudioToggle: View {
    let asset: PanelBackgroundAsset?
    let isAudioEnabled: Bool
    let reduceMotion: Bool
    let setAudioEnabled: (Bool) -> Void

    @Environment(\.panelAccessibilityIdentifierReporter) private var identifierReporter
    @Environment(\.panelAccessibilityLabelReporter) private var labelReporter
    @Environment(\.panelAccessibilityActionReporter) private var actionReporter

    private let identifier = "panel-background-audio-toggle"

    var body: some View {
        if PanelBackgroundMenuPolicy.showsAudioToggle(for: asset) {
            Button(action: toggleAudio) {
                Image(systemName: isAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .buttonStyle(.plain)
            .disabled(reduceMotion)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)
            .onAppear {
                identifierReporter?(identifier)
                labelReporter?(accessibilityLabel)
                actionReporter?(identifier, toggleAudio)
            }
        }
    }

    private var accessibilityLabel: String {
        isAudioEnabled ? "关闭视频背景声音" : "开启视频背景声音"
    }

    private func toggleAudio() {
        guard !reduceMotion else { return }
        setAudioEnabled(!isAudioEnabled)
    }
}

struct PanelBackgroundReduceMotionMessage: View {
    let asset: PanelBackgroundAsset?
    let isEnabled: Bool
    let reduceMotion: Bool

    @Environment(\.panelAccessibilityIdentifierReporter) private var identifierReporter
    @Environment(\.panelAccessibilityLabelReporter) private var labelReporter

    private let identifier = "panel-reduce-motion-message"
    private let message = "减少动态效果已开启"

    var body: some View {
        if isEnabled, asset?.isDynamic == true, reduceMotion {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelTextReadability(.secondary)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(message)
                .onAppear {
                    identifierReporter?(identifier)
                    labelReporter?(message)
                }
        }
    }
}
