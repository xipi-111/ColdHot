import SwiftUI

private struct DetailSectionTintKey: EnvironmentKey {
    static let defaultValue: Color = .secondary
}

private extension EnvironmentValues {
    var detailSectionTint: Color {
        get { self[DetailSectionTintKey.self] }
        set { self[DetailSectionTintKey.self] = newValue }
    }
}

struct MetricCard<ExpandedContent: View>: View {
    let metric: MetricKind
    let value: String
    let detail: String
    var progress: Double?
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let expandedContent: () -> ExpandedContent

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(metric.tint)
                        .frame(width: 28, height: 28)
                        .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(metric.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(value)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }

                        if let progress {
                            ProgressView(value: min(max(progress, 0), 1))
                                .tint(metric.tint)
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                        }

                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .padding(11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(metric.title)
            .accessibilityValue("\(value)，\(detail)")
            .accessibilityHint(isExpanded ? "收起详细信息" : "展开详细信息")

            if isExpanded {
                Divider().padding(.horizontal, 11)
                VStack(alignment: .leading, spacing: 12) {
                    expandedContent()
                }
                .environment(\.detailSectionTint, metric.tint)
                .padding(11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.detailSectionTint) private var titleTint

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleTint)
            content()
        }
    }
}

struct DetailValueRow: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ProcessActivityList: View {
    let title: String
    let processes: [ProcessActivity]
    let value: (ProcessActivity) -> String

    var body: some View {
        DetailSection(title: title) {
            if processes.isEmpty {
                Text("正在建立采样基线…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(processes) { process in
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(value(process))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
