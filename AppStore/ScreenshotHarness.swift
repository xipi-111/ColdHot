import AppKit
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableVersion: String?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    func checkForUpdates() {}
}

/// Renders the real App Store dashboard inside an App Store screenshot-sized
/// window. This file is intentionally not part of the ColdHot Xcode target.
#if !SCREENSHOT_RENDERER
@main
struct ColdHotScreenshotApp: App {
    @StateObject private var settings: MonitorSettings
    @StateObject private var monitor: PerformanceMonitor
    @StateObject private var dockController: DockDelayController
    @StateObject private var panelBackgroundStore: PanelBackgroundStore
    @StateObject private var updateController: UpdateController

    private let shot: ScreenshotKind

    init() {
        let executableName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        shot = ScreenshotKind(
            argument: CommandLine.arguments.dropFirst().first ?? bundleIdentifier + executableName
        )

        let suiteName = "com.xipiyoung.ColdHot.ScreenshotHarness"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = MonitorSettings(defaults: defaults)
        for metric in BuildVariant.availableMetrics {
            settings.setEnabled(true, for: metric)
        }

        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: PerformanceMonitor(settings: settings))
        _dockController = StateObject(wrappedValue: DockDelayController())
        _panelBackgroundStore = StateObject(wrappedValue: PanelBackgroundStore())
        _updateController = StateObject(wrappedValue: UpdateController())
    }

    var body: some Scene {
        WindowGroup("ColdHot App Store Screenshot") {
            ScreenshotCanvas(
                shot: shot,
                monitor: monitor,
                settings: settings,
                dockController: dockController,
                panelBackgroundStore: panelBackgroundStore,
                updateController: updateController
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1_280, height: 800)

        Settings {
            SettingsView(
                settings: settings,
                panelBackgroundStore: panelBackgroundStore,
                monitor: monitor,
                updateController: updateController
            )
        }
    }
}
#endif

enum ScreenshotKind: String, CaseIterable {
    case overview
    case cpu
    case battery

    init(argument: String?) {
        let normalized = argument?.lowercased() ?? ""
        if normalized.contains("battery") {
            self = .battery
        } else if normalized.contains("cpu") {
            self = .cpu
        } else {
            self = .overview
        }
    }

    var eyebrow: String {
        switch self {
        case .overview: "轻量原生性能监控"
        case .cpu: "按需展开详细指标"
        case .battery: "状态始终留在本机"
        }
    }

    var title: String {
        switch self {
        case .overview: "性能，一眼看清"
        case .cpu: "细节，需要时再看"
        case .battery: "电量与热状态，随时掌握"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            "CPU、内存、网络、热状态与电池，\n安静地常驻菜单栏。"
        case .cpu:
            "系统负载、每核心利用率和内存构成，\n只在展开对应卡片时采样。"
        case .battery:
            "无需账号，没有广告与分析 SDK，\n监控数据不会上传。"
        }
    }

    var expandedMetric: MetricKind? {
        switch self {
        case .overview: nil
        case .cpu: .cpu
        case .battery: .battery
        }
    }

    var accent: Color {
        switch self {
        case .overview: .green
        case .cpu: .blue
        case .battery: .green
        }
    }

    var fileName: String {
        switch self {
        case .overview: "01-overview.png"
        case .cpu: "02-cpu-details.png"
        case .battery: "03-battery-privacy.png"
        }
    }
}

struct ScreenshotCanvas: View {
    let shot: ScreenshotKind
    @ObservedObject var monitor: PerformanceMonitor
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var dockController: DockDelayController
    @ObservedObject var panelBackgroundStore: PanelBackgroundStore
    @ObservedObject var updateController: UpdateController

    var body: some View {
        artwork
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    monitor.setExpandedMetric(shot.expandedMetric)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    renderPNG()
                }
            }
    }

    var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.050, blue: 0.045),
                    Color(red: 0.075, green: 0.095, blue: 0.085),
                    Color(red: 0.025, green: 0.030, blue: 0.032)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(shot.accent.opacity(0.18))
                .frame(width: 620, height: 620)
                .blur(radius: 90)
                .offset(x: 420, y: -260)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(x: -520, y: 330)

            HStack(spacing: 78) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.green.opacity(0.18))
                            Image(systemName: "gauge.with.dots.needle.50percent")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        .frame(width: 48, height: 48)

                        Text("ColdHot")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                    }
                    .padding(.bottom, 76)

                    Text(shot.eyebrow.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(shot.accent)
                        .padding(.bottom, 18)

                    Text(shot.title)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .tracking(-1.6)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 24)

                    Text(shot.subtitle)
                        .font(.system(size: 23, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineSpacing(8)

                    Spacer()

                    Label("macOS 14 或更高版本", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(width: 570, alignment: .leading)

                DashboardView(
                    monitor: monitor,
                    settings: settings,
                    dockController: dockController,
                    panelBackgroundStore: panelBackgroundStore,
                    updateController: updateController,
                    initialVisibleDetailsMetric: shot.expandedMetric
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.48), radius: 34, y: 24)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 64)
        }
        .frame(width: 1_280, height: 800)
        .preferredColorScheme(.dark)
    }

    @MainActor
    func renderPNG() {
        let hostingView = NSHostingView(rootView: artwork)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_280, height: 800)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1_280,
            pixelsHigh: 800,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        bitmap.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }

        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots/zh-Hans", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try png.write(to: directory.appendingPathComponent(shot.fileName), options: .atomic)
        } catch {
            fputs("Screenshot export failed: \(error)\n", stderr)
        }
    }
}
