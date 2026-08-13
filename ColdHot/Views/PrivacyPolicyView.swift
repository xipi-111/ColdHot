import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("隐私政策")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("最后更新：2026 年 8 月 12 日")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    policySection(
                        "数据处理",
                        "ColdHot 的性能、温度、电池、网络与进程数据只在本机即时读取和显示。应用不创建账户，不包含广告或分析 SDK，也不会把监控结果上传给开发者或第三方。"
                    )
                    policySection(
                        "网络延迟测试",
                        "网络延迟详细项默认关闭。用户主动开启并展开网络卡片后，应用约每 10 秒向 1.1.1.1:443 发起一次 TCP 连接，用于测量建连延迟；不会发送监控数据。"
                    )
                    policySection(
                        "本地设置",
                        "指标选择、刷新间隔和界面偏好保存在应用自己的本地偏好中。删除应用数据即可移除这些设置。"
                    )
                    policySection(
                        "版本差异",
                        BuildVariant.isAppStore
                            ? "App Store 版运行在 App Sandbox 中，只使用该版本允许的系统能力。"
                            : "官网版可读取更多本机传感器并提供 Dock 快捷控制；这些操作仍只在本机执行。"
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 520, height: 500)
    }

    private func policySection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
