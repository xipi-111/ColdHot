import AppKit
import Combine
import SwiftUI

private func expect(
    _ condition: @autoclosure () -> Bool,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard condition() else {
        fatalError("Check failed", file: file, line: line)
    }
}

@MainActor
final class UpdateController: ObservableObject {
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    func checkForUpdates() {}
}

@main
enum SettingsVisualCheck {
    @MainActor
    static func main() throws {
        expect(SettingsLayout.defaultContentSize == CGSize(width: 920, height: 720))
        expect(SettingsLayout.minimumContentSize == CGSize(width: 860, height: 680))
        expect(SettingsLayout.sidebarWidth == 204)
        expect(SettingsLayout.sectionCornerRadius == 14)
        expect(SettingsLayout.sidebarSelectionCornerRadius == 10)
        expect(SettingsLayout.standardRowHeight == 48)
        expect(SettingsLayout.sliderRowHeight == 64)
        expect(SettingsLayout.compactRowHeight == 40)

        let defaultPageMetrics = SettingsLayout.pageMetrics(
            mainViewportSize: CGSize(width: 716, height: 720)
        )
        expect(defaultPageMetrics.horizontalPadding == 34)
        expect(defaultPageMetrics.topPadding == 48)
        expect(defaultPageMetrics.titleToContentSpacing == 32)
        let minimumPageMetrics = SettingsLayout.pageMetrics(
            mainViewportSize: CGSize(width: 656, height: 680)
        )
        expect(minimumPageMetrics.horizontalPadding == 30)
        expect(minimumPageMetrics.topPadding == 42)
        expect(minimumPageMetrics.titleToContentSpacing == 28)

        let defaultColumns = SettingsAppearanceColumns.resolve(contentWidth: 648)
        expect(defaultColumns.order == [.preview, .controls])
        expect(defaultColumns.previewWidth == 328)
        expect(defaultColumns.controlsWidth == 300)
        expect(defaultColumns.spacing == 20)
        expect(defaultColumns.previewHeight == 520)
        let minimumColumns = SettingsAppearanceColumns.resolve(contentWidth: 596)
        expect(minimumColumns.order == [.preview, .controls])
        expect(minimumColumns.previewWidth == 304)
        expect(minimumColumns.controlsWidth == 276)
        expect(minimumColumns.spacing == 16)
        expect(minimumColumns.previewHeight == 488)
        expect(PanelLayout.width == 370)
        expect(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 370) == 1)
        expect(abs(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 296) - 0.8) < 0.0001)
        expect(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 500) == 1)
        expect(abs(SettingsPreviewScale.factor(
            contentSize: CGSize(width: 370, height: 650),
            availableSize: CGSize(width: 328, height: 520)
        ) - 0.8) < 0.0001)
        expect(SettingsPage.allCases.map(\.rawValue) == [
            "外观", "指标", "阈值提醒", "通用", "关于"
        ])
        expect(!SettingsPage.appearance.requiresScrolling)
        expect(SettingsPage.metrics.requiresScrolling)
        expect(SettingsPage.alerts.requiresScrolling)
        expect(!SettingsPage.general.requiresScrolling)
        expect(!SettingsPage.about.requiresScrolling)
        expect(SettingsSidebarSelection.move(from: .appearance, direction: .up) == .about)
        expect(SettingsSidebarSelection.move(from: .about, direction: .down) == .appearance)
        expect(SettingsSidebarSelection.move(from: .metrics, direction: .down) == .alerts)
        verifySidebarActivation()

        let suiteName = "com.xipiyoung.ColdHot.settings-visual-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        settings.applyPreset(.everyday)
        settings.setPanelBackgroundEnabled(true)
        settings.setPanelBackgroundZoom(1.35)
        settings.setPanelBackgroundPosition(x: 0.30, y: -0.20)
        let monitor = PerformanceMonitor(settings: settings)
        let backgroundStore = PanelBackgroundStore(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "coldhot-settings-visual-\(UUID().uuidString)",
                isDirectory: true
            )
        )
        try backgroundStore.importImage(
            from: URL(fileURLWithPath: "Artwork/ColdHot-AppIcon-Pulse-Source.png")
        )

        let outputDirectory = CommandLine.arguments.dropFirst().first
            ?? "/tmp/coldhot-settings-a1"
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        let appearances: [(slug: String, name: NSAppearance.Name)] = [
            ("aqua", .aqua),
            ("darkAqua", .darkAqua)
        ]
        var renderedCaseCount = 0
        for appearance in appearances {
            for page in SettingsPage.allCases {
                let sizes: [(slug: String, value: CGSize)] = [
                    ("920x720", SettingsLayout.defaultContentSize),
                    ("860x680", SettingsLayout.minimumContentSize)
                ]
                for size in sizes {
                    let view = SettingsView(
                        settings: settings,
                        panelBackgroundStore: backgroundStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        initialPage: page
                    )
                    let outputPath = outputDirectory
                        + "/\(appearance.slug)-\(page.slug)-\(size.slug).png"
                    try render(
                        view,
                        page: page,
                        appearance: appearance.name,
                        size: size.value,
                        outputPath: outputPath
                    )
                    renderedCaseCount += 1
                    print(outputPath)
                }
            }
        }
        expect(renderedCaseCount == appearances.count * SettingsPage.allCases.count * 2)
        if ProcessInfo.processInfo.environment["COLDHOT_SETTINGS_VISUAL_HOLD"] == "1" {
            RunLoop.main.run()
        }
    }

    @MainActor
    private static func verifySidebarActivation() {
        let selection = SidebarSelectionStore()
        let hostingView = NSHostingView(
            rootView: SettingsSidebar(
                selection: Binding(
                    get: { selection.value },
                    set: { selection.value = $0 }
                ),
                versionText: "1.3.1 (18)"
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 204, height: 680)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        expect(selection.value == .appearance)
        // At this fixed 680pt sidebar height, the point is centered in the
        // second visible navigation row (Metrics). Delivering real AppKit
        // mouse events exercises the SwiftUI Button action and selection
        // binding instead of injecting SettingsView.initialPage.
        sendMouseClick(to: window, at: NSPoint(x: 80, y: 560))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(selection.value == .metrics)
        window.orderOut(nil)
    }

    @MainActor
    private static func sendMouseClick(to window: NSWindow, at point: NSPoint) {
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: eventType,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: eventType == .leftMouseDown ? 1 : 0
            ) else {
                fatalError("Unable to synthesize sidebar click")
            }
            window.sendEvent(event)
        }
    }

    @MainActor
    private static func render(
        _ view: SettingsView,
        page: SettingsPage,
        appearance: NSAppearance.Name,
        size: CGSize,
        outputPath: String
    ) throws {
        let identifiers = AccessibilityIdentifierStore()
        let labels = AccessibilityLabelStore()
        let hostingView = NSHostingView(
            rootView: view
                .environment(
                    \.settingsAccessibilityIdentifierReporter,
                    { identifiers.values.insert($0) }
                )
                .environment(
                    \.settingsAccessibilityLabelReporter,
                    { labels.values.insert($0) }
                )
        )
        hostingView.appearance = NSAppearance(named: appearance)
        let preconfigurationContentSize = CGSize(width: 880, height: 690)
        hostingView.frame = CGRect(origin: .zero, size: preconfigurationContentSize)
        expect(hostingView.frame.size != SettingsLayout.defaultContentSize)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let splitViews = descendants(of: hostingView).compactMap { $0 as? NSSplitView }
        expect(splitViews.isEmpty)
        expect(window.contentMinSize == SettingsLayout.minimumContentSize)
        expect(window.contentView?.bounds.size == SettingsLayout.defaultContentSize)
        expect(window.styleMask.contains(.fullSizeContentView))
        expect(window.titleVisibility == .hidden)
        expect(window.titlebarAppearsTransparent)
        expect(window.titlebarSeparatorStyle == .none)
        expect(window.toolbar?.isVisible != true)

        expect(identifiers.values.contains("settings-sidebar"))
        expect(identifiers.values.contains("settings-page-\(page.slug)"))
        expect(identifiers.values.contains(firstSectionIdentifier(for: page)))
        if page == .appearance {
            expect(labels.values.contains("菜单面板外观预览"))
            expect(identifiers.values.contains("settings-appearance-preview-column"))
            expect(identifiers.values.contains("settings-appearance-controls-column"))
        }
        if page == .about {
            expect(
                identifiers.values.contains(
                    "settings-section-about-1-header-action"
                )
            )
            expect(labels.values.contains("重新检测设备能力"))
        }

        // The first configuration owns only the initial default. A later user
        // resize must survive activation and resize-driven reconfiguration.
        let userResizedContentSize = SettingsLayout.minimumContentSize
        window.setContentSize(userResizedContentSize)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard window.titleVisibility == .hidden,
              window.titlebarAppearsTransparent else {
            fatalError("Settings title bar configuration must survive window activation")
        }
        expect(window.contentMinSize == SettingsLayout.minimumContentSize)
        expect(window.contentView?.bounds.size == userResizedContentSize)

        window.contentMinSize = .zero
        NotificationCenter.default.post(
            name: NSWindow.didResizeNotification,
            object: window
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(window.contentMinSize == SettingsLayout.minimumContentSize)
        expect(window.contentView?.bounds.size == userResizedContentSize)

        window.setContentSize(size)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(window.contentView?.bounds.size == size)

        // This PNG intentionally caches only SwiftUI content. Actual traffic
        // lights, titlebar composition, and backdrop-dependent sidebar glass
        // remain a manual gate in the installed Settings Scene.
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create settings preview")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode settings preview")
        }
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        window.orderOut(nil)
    }

    @MainActor
    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { subview in
            [subview] + descendants(of: subview)
        }
    }

    private static func firstSectionIdentifier(for page: SettingsPage) -> String {
        if page == .general {
            if BuildVariant.channel == .direct {
                return "settings-section-general-0"
            }
            if BuildVariant.supportsDockControl {
                return "settings-section-general-1"
            }
            return "settings-section-general-2"
        }
        return "settings-section-\(page.slug)-0"
    }
}

@MainActor
private final class AccessibilityIdentifierStore {
    var values: Set<String> = []
}

@MainActor
private final class AccessibilityLabelStore {
    var values: Set<String> = []
}

@MainActor
private final class SidebarSelectionStore {
    var value: SettingsPage = .appearance
}
