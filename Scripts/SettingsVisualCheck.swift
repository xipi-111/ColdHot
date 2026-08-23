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
        let systemKnobRect = CGRect(x: 0, y: 10, width: 17, height: 100)
        expect(
            SettingsScrollbarGeometry.visibleThumbRect(in: systemKnobRect)
                == CGRect(x: 13, y: 10, width: 4, height: 100)
        )
        let stylePreservationScrollView = NSScrollView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        stylePreservationScrollView.scrollerStyle = .legacy
        stylePreservationScrollView.autohidesScrollers = false
        stylePreservationScrollView.documentView = NSView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 600)
        )
        SettingsScrollbarConfiguration.apply(to: stylePreservationScrollView)
        stylePreservationScrollView.layoutSubtreeIfNeeded()
        expect(stylePreservationScrollView.scrollerStyle == .legacy)
        expect(stylePreservationScrollView.verticalScroller is SettingsThinScroller)
        guard let configuredScroller = stylePreservationScrollView.verticalScroller else {
            fatalError("Missing configured settings scroller")
        }
        expect(
            abs(
                configuredScroller.bounds.width
                    - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            ) < 0.5
        )

        let defaultPageMetrics = SettingsLayout.pageMetrics(
            mainViewportSize: CGSize(width: 716, height: 720)
        )
        expect(defaultPageMetrics.horizontalPadding == 34)
        expect(defaultPageMetrics.topPadding == 48)
        let minimumPageMetrics = SettingsLayout.pageMetrics(
            mainViewportSize: CGSize(width: 656, height: 680)
        )
        expect(minimumPageMetrics.horizontalPadding == 30)
        expect(minimumPageMetrics.topPadding == 42)

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
        try runAsyncCheck {
            try await backgroundStore.importBackground(
                from: URL(fileURLWithPath: "Artwork/ColdHot-AppIcon-Pulse-Source.png")
            )
        }
        expect(backgroundStore.asset?.kind == .staticImage)

        let outputDirectory = CommandLine.arguments.dropFirst().first
            ?? "/tmp/coldhot-settings-a1"
        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true
        )

        if ProcessInfo.processInfo.environment["COLDHOT_SETTINGS_PROCESSING_ONLY"] == "1" {
            let focusedFixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "coldhot-settings-processing-fixtures-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: focusedFixtureRoot,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: focusedFixtureRoot) }
            try verifyEmptyAndProcessingPresentation(
                settings: settings,
                monitor: monitor,
                fixtureRoot: focusedFixtureRoot,
                outputDirectory: outputDirectory
            )
            return
        }

        if ProcessInfo.processInfo.environment["COLDHOT_TASK6_OPERATIONS_ONLY"] == "1" {
            let focusedFixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "coldhot-settings-task6-operation-fixtures-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: focusedFixtureRoot,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: focusedFixtureRoot) }
            try runAsyncCheck {
                try await verifyBackgroundOperationRecovery(in: focusedFixtureRoot)
            }
            return
        }

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
                    _ = try render(
                        view,
                        page: page,
                        appearance: appearance.name,
                        size: size.value,
                        outputPath: outputPath,
                        expectedBackgroundTypeLabel: page == .appearance ? "静态图片" : nil,
                        expectsPreviewAudioToggle: page == .appearance ? false : nil
                    )
                    renderedCaseCount += 1
                    print(outputPath)
                }
            }
        }

        let expandedFixtures: [(
            slug: String,
            parent: MetricKind,
            tier: ThresholdMetric?,
            scrollFraction: Double,
            requiredIdentifiers: Set<String>
        )] = [
            (
                "cpu",
                .cpu,
                .cpuUsage,
                0.50,
                [
                    "settings-threshold-tiers-cpuUsage",
                    "settings-threshold-cpuUsage-level2",
                    "settings-threshold-cpuUsage-level3"
                ]
            ),
            (
                "battery",
                .battery,
                .batteryPercentage,
                1,
                [
                    "settings-threshold-tiers-batteryPercentage",
                    "settings-threshold-batteryPercentage-level2",
                    "settings-threshold-batteryPercentage-level3"
                ]
            ),
            (
                "thermal",
                .thermal,
                nil,
                0.88,
                ["settings-threshold-thermalState-fixed-mapping"]
            )
        ]
        for fixture in expandedFixtures {
            settings.setThresholdEnabled(true, for: fixture.tier ?? .thermalState)
        }
        for appearance in appearances {
            for size in [
                (slug: "920x720", value: SettingsLayout.defaultContentSize),
                (slug: "860x680", value: SettingsLayout.minimumContentSize)
            ] {
                for fixture in expandedFixtures {
                    let view = SettingsView(
                        settings: settings,
                        panelBackgroundStore: backgroundStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        initialPage: .alerts,
                        initialExpandedThresholdMetrics: [fixture.parent],
                        initialExpandedThresholdTiers: Set([fixture.tier].compactMap { $0 })
                    )
                    let outputPath = outputDirectory
                        + "/\(appearance.slug)-alerts-expanded-\(fixture.slug)-\(size.slug).png"
                    _ = try render(
                        view,
                        page: .alerts,
                        appearance: appearance.name,
                        size: size.value,
                        outputPath: outputPath,
                        additionalRequiredIdentifiers: fixture.requiredIdentifiers,
                        scrollFraction: fixture.scrollFraction
                    )
                    renderedCaseCount += 1
                    print(outputPath)
                }
            }
        }
        expect(
            renderedCaseCount
                == appearances.count
                    * (SettingsPage.allCases.count * 2 + expandedFixtures.count * 2)
        )

        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "coldhot-settings-task6-fixtures-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try runAsyncCheck {
            try await verifyBackgroundOperationRecovery(in: fixtureRoot)
            try await verifyPreviewAudioLifecycle(
                settings: settings,
                monitor: monitor,
                fixtureRoot: fixtureRoot,
                outputDirectory: outputDirectory
            )
        }
        try verifyEmptyAndProcessingPresentation(
            settings: settings,
            monitor: monitor,
            fixtureRoot: fixtureRoot,
            outputDirectory: outputDirectory
        )
        if ProcessInfo.processInfo.environment["COLDHOT_SETTINGS_VISUAL_HOLD"] == "1" {
            RunLoop.main.run()
        }
    }

    @MainActor
    private static func runAsyncCheck(
        _ operation: @escaping @MainActor () async throws -> Void
    ) throws {
        let resultBox = SettingsAsyncResultBox()
        Task { @MainActor in
            do {
                try await operation()
                resultBox.result = .success(())
            } catch {
                resultBox.result = .failure(error)
            }
        }
        while resultBox.result == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try resultBox.result?.get()
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
                versionText: "1.5.1 (25)"
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
        outputPath: String,
        expectedBackgroundTypeLabel: String? = nil,
        expectsPreviewAudioToggle: Bool? = nil,
        additionalRequiredIdentifiers: Set<String> = [],
        scrollFraction: Double? = nil
    ) throws -> SettingsRenderReport {
        let identifiers = AccessibilityIdentifierStore()
        let labels = AccessibilityLabelStore()
        let actions = AccessibilityActionStore()
        let controlEnabledStates = SettingsControlEnabledStore()
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
                .environment(
                    \.panelAccessibilityIdentifierReporter,
                    { identifiers.values.insert($0) }
                )
                .environment(
                    \.panelAccessibilityLabelReporter,
                    { labels.values.insert($0) }
                )
                .environment(
                    \.panelAccessibilityActionReporter,
                    { identifier, action in actions.values[identifier] = action }
                )
                .environment(
                    \.settingsControlEnabledReporter,
                    { identifier, isEnabled in
                        controlEnabledStates.values[identifier] = isEnabled
                    }
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
        guard window.contentView?.bounds.size == SettingsLayout.defaultContentSize else {
            let classes = descendants(of: hostingView).map { String(describing: type(of: $0)) }
            fatalError("Unexpected configured size; descendants: \(classes)")
        }
        expect(window.styleMask.contains(.fullSizeContentView))
        expect(window.titleVisibility == .hidden)
        expect(window.titlebarAppearsTransparent)
        expect(window.titlebarSeparatorStyle == .none)
        expect(window.toolbar?.isVisible != true)

        expect(identifiers.values.contains("settings-sidebar"))
        expect(identifiers.values.contains("settings-page-\(page.slug)"))
        expect(identifiers.values.contains(firstSectionIdentifier(for: page)))
        expect(labels.values.contains(page.rawValue))
        if page == .appearance {
            expect(labels.values.contains("菜单面板外观预览"))
            expect(identifiers.values.contains("settings-appearance-preview-column"))
            expect(identifiers.values.contains("settings-appearance-controls-column"))
            if let expectedBackgroundTypeLabel {
                expect(labels.values.contains("自定义背景"))
                expect(labels.values.contains("当前：\(expectedBackgroundTypeLabel)"))
                expect(
                    labels.values.contains(
                        "支持图片、GIF、MP4、MOV、M4V 及系统视频"
                    )
                )
                expect(labels.values.contains("更换背景…"))
            }
            if let expectsPreviewAudioToggle {
                expect(
                    identifiers.values.contains("settings-preview-audio-toggle")
                        == expectsPreviewAudioToggle
                )
            }
        }
        if page == .about {
            expect(
                identifiers.values.contains(
                    "settings-section-about-1-header-action"
                )
            )
            expect(labels.values.contains("重新检测设备能力"))
        }
        if page == .alerts {
            let requiredIdentifiers: Set<String> = [
                "settings-section-alerts-2",
                "settings-threshold-color-level1-system",
                "settings-threshold-color-level1-picker",
                "settings-threshold-color-level2-picker",
                "settings-threshold-color-level3-picker",
                "settings-threshold-colors-reset",
                "settings-threshold-preview-level1",
                "settings-threshold-preview-level2",
                "settings-threshold-preview-level3"
            ]
            let missingIdentifiers = requiredIdentifiers.subtracting(identifiers.values)
            guard missingIdentifiers.isEmpty else {
                fatalError("Missing alert identifiers: \(missingIdentifiers.sorted())")
            }
            expect(labels.values.contains("恢复推荐颜色"))
        }
        let missingAdditionalIdentifiers = additionalRequiredIdentifiers
            .subtracting(identifiers.values)
        guard missingAdditionalIdentifiers.isEmpty else {
            fatalError(
                "Missing fixture identifiers: \(missingAdditionalIdentifiers.sorted())"
            )
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
        var pageScrollView: NSScrollView?
        if page.requiresScrolling {
            let scrollViews = descendants(of: hostingView).compactMap { $0 as? NSScrollView }
            guard let resolvedPageScrollView = scrollViews.max(by: {
                $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
            }) else {
                fatalError("Missing settings page scroll view")
            }
            pageScrollView = resolvedPageScrollView
            let frameInHostingView = resolvedPageScrollView.convert(
                resolvedPageScrollView.bounds,
                to: hostingView
            )
            expect(abs(frameInHostingView.maxX - hostingView.bounds.maxX) < 0.5)
            expect(resolvedPageScrollView.verticalScroller is SettingsThinScroller)
        }
        if let scrollFraction {
            guard let pageScrollView, let documentView = pageScrollView.documentView else {
                fatalError("Missing scrollable settings document")
            }
            let maximumY = max(
                0,
                documentView.bounds.height - pageScrollView.contentView.bounds.height
            )
            pageScrollView.contentView.scroll(
                to: NSPoint(x: 0, y: maximumY * min(max(scrollFraction, 0), 1))
            )
            pageScrollView.reflectScrolledClipView(pageScrollView.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        // This PNG intentionally caches only SwiftUI content. Actual traffic
        // lights, titlebar composition, and backdrop-dependent sidebar glass
        // remain a manual gate in the installed Settings Scene.
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create settings preview")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        if page == .about,
           appearance == .darkAqua,
           size == SettingsLayout.defaultContentSize {
            let brightPixels = brightPixelCount(
                inTopOriginRect: CGRect(x: 220, y: 38, width: 300, height: 62),
                bitmap: bitmap,
                logicalSize: hostingView.bounds.size
            )
            expect(brightPixels < 1_800)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode settings preview")
        }
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        window.orderOut(nil)
        return SettingsRenderReport(
            identifiers: identifiers.values,
            labels: labels.values,
            actions: actions.values,
            controlEnabledStates: controlEnabledStates.values
        )
    }

    @MainActor
    private static func verifyPreviewAudioLifecycle(
        settings: MonitorSettings,
        monitor: PerformanceMonitor,
        fixtureRoot: URL,
        outputDirectory: String
    ) async throws {
        settings.setPanelBackgroundEnabled(true)
        settings.setPanelBackgroundAudioEnabled(false)

        for (kind, hasAudio, shouldExposeAudio) in [
            (PanelBackgroundMediaKind.staticImage, false, false),
            (.convertedGIF, false, false),
            (.video, false, false),
            (.video, true, true)
        ] {
            let store = try makeFixtureStore(
                in: fixtureRoot,
                name: "eligibility-\(kind.rawValue)-\(hasAudio)",
                kind: kind,
                hasAudio: hasAudio
            )
            let session = makePreviewSession()
            let view = SettingsView(
                settings: settings,
                panelBackgroundStore: store,
                monitor: monitor,
                updateController: UpdateController(),
                previewSession: session
            )
            let report = try render(
                view,
                page: .appearance,
                appearance: .aqua,
                size: SettingsLayout.minimumContentSize,
                outputPath: outputDirectory
                    + "/fixture-eligibility-\(kind.rawValue)-\(hasAudio).png",
                expectedBackgroundTypeLabel: backgroundTypeLabel(for: kind),
                expectsPreviewAudioToggle: shouldExposeAudio
            )
            expect(
                report.identifiers.contains("settings-preview-audio-toggle")
                    == shouldExposeAudio
            )
            expect(
                (report.actions["settings-preview-audio-toggle"] != nil)
                    == shouldExposeAudio
            )
            if shouldExposeAudio {
                expect(report.labels.contains("开启预览声音"))
                expect(report.labels.contains("仅本次预览，离开后恢复静音"))
                report.actions["settings-preview-audio-toggle"]?()
                expect(session.isAudioRequested)
                expect(!session.controller.player.isMuted)
            }
            expect(!settings.isPanelBackgroundAudioEnabled)
            session.didDisappear()
        }

        let audioStore = try makeFixtureStore(
            in: fixtureRoot,
            name: "audio-layout",
            kind: .video,
            hasAudio: true
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for size in [SettingsLayout.defaultContentSize, SettingsLayout.minimumContentSize] {
                let session = makePreviewSession()
                session.didAppear(
                    asset: audioStore.asset,
                    isEnabled: settings.isPanelBackgroundEnabled,
                    reduceMotion: false
                )
                await Task.yield()
                session.setAudioRequested(
                    true,
                    asset: audioStore.asset,
                    isEnabled: settings.isPanelBackgroundEnabled,
                    reduceMotion: false
                )
                let report = try render(
                    SettingsView(
                        settings: settings,
                        panelBackgroundStore: audioStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        previewSession: session
                    ),
                    page: .appearance,
                    appearance: appearance,
                    size: size,
                    outputPath: outputDirectory
                        + "/fixture-audio-video-\(appearance.rawValue)-"
                        + "\(Int(size.width))x\(Int(size.height)).png",
                    expectedBackgroundTypeLabel: "视频",
                    expectsPreviewAudioToggle: true
                )
                expect(report.labels.contains("关闭预览声音"))
                expect(report.labels.contains("仅本次预览，离开后恢复静音"))
                report.actions["settings-preview-audio-toggle"]?()
                expect(!session.isAudioRequested)
                expect(session.controller.player.isMuted)
                expect(!settings.isPanelBackgroundAudioEnabled)
                session.didDisappear()
            }
        }

        let reducedStore = try makeFixtureStore(
            in: fixtureRoot,
            name: "reduce-motion-audio",
            kind: .video,
            hasAudio: true
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for size in [SettingsLayout.defaultContentSize, SettingsLayout.minimumContentSize] {
                let reducedSession = makePreviewSession()
                let report = try render(
                    SettingsView(
                        settings: settings,
                        panelBackgroundStore: reducedStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        previewSession: reducedSession,
                        reduceMotionOverride: true
                    ),
                    page: .appearance,
                    appearance: appearance,
                    size: size,
                    outputPath: outputDirectory
                        + "/fixture-reduce-motion-\(appearance.rawValue)-"
                        + "\(Int(size.width))x\(Int(size.height)).png",
                    expectedBackgroundTypeLabel: "视频",
                    expectsPreviewAudioToggle: true
                )
                expect(report.identifiers.contains("settings-preview-audio-toggle"))
                expect(
                    report.labels.contains(
                        "减少动态效果已开启，动态背景与声音已暂停"
                    )
                )
                report.actions["settings-preview-audio-toggle"]?()
                expect(!reducedSession.isAudioRequested)
                let intent = reducedSession.intent(
                    asset: reducedStore.asset,
                    isEnabled: true,
                    reduceMotion: true
                )
                expect(!intent.shouldPlay)
                expect(intent.shouldMute)
            }
        }
    }

    @MainActor
    private static func verifyBackgroundOperationRecovery(in fixtureRoot: URL) async throws {
        let suiteName = "com.xipiyoung.ColdHot.settings-operation-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create operation defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = fixtureRoot.appendingPathComponent("operation-rollback", isDirectory: true)
        let sourceURL = URL(fileURLWithPath: "Artwork/ColdHot-AppIcon-Pulse-Source.png")
        let initialStore = PanelBackgroundStore(directoryURL: directory)
        try await initialStore.importBackground(from: sourceURL)
        let previousID = initialStore.asset?.id
        let settings = MonitorSettings(defaults: defaults)
        settings.setPanelBackgroundEnabled(false)
        settings.setPanelBackgroundZoom(1.65)
        settings.setPanelBackgroundPosition(x: 0.45, y: -0.35)
        settings.setPanelBackgroundAudioEnabled(true)

        let rollbackStore = PanelBackgroundStore(
            directoryURL: directory,
            writeManifest: { _, _ in throw PanelBackgroundImportError.unableToWrite }
        )
        let rollbackResult = await SettingsPanelBackgroundOperations.importBackground(
            from: sourceURL,
            store: rollbackStore,
            settings: settings
        )
        expect(!rollbackResult.didCommit)
        expect(rollbackResult.error?.localizedDescription
            == PanelBackgroundImportError.unableToWrite.localizedDescription)
        expect(rollbackStore.asset?.id == previousID)
        expect(!settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1.65)
        expect(settings.panelBackgroundPositionX == 0.45)
        expect(settings.panelBackgroundPositionY == -0.35)
        expect(settings.isPanelBackgroundAudioEnabled)

        let corruptURL = fixtureRoot.appendingPathComponent("corrupt.mp4")
        try Data("not media".utf8).write(to: corruptURL)
        let corruptResult = await SettingsPanelBackgroundOperations.importBackground(
            from: corruptURL,
            store: rollbackStore,
            settings: settings
        )
        expect(!corruptResult.didCommit)
        expect(rollbackStore.asset?.id == previousID)
        expect(!settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1.65)
        expect(settings.panelBackgroundPositionX == 0.45)
        expect(settings.panelBackgroundPositionY == -0.35)
        expect(settings.isPanelBackgroundAudioEnabled)

        let cleanupManager = SettingsCleanupFailingFileManager()
        let cleanupDirectory = fixtureRoot.appendingPathComponent(
            "operation-cleanup",
            isDirectory: true
        )
        let cleanupStore = PanelBackgroundStore(
            directoryURL: cleanupDirectory,
            fileManager: cleanupManager
        )
        try await cleanupStore.importBackground(from: sourceURL)
        let cleanupPreviousID = cleanupStore.asset?.id
        let referencedFiles = try FileManager.default.contentsOfDirectory(
            at: cleanupDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("media-") }
        expect(referencedFiles.count == 1)
        cleanupManager.blockedRemovalPath = referencedFiles[0].standardizedFileURL.path
        settings.setPanelBackgroundEnabled(false)
        settings.setPanelBackgroundZoom(1.8)
        settings.setPanelBackgroundPosition(x: -0.6, y: 0.4)
        settings.setPanelBackgroundAudioEnabled(true)
        let cleanupImportResult = await SettingsPanelBackgroundOperations.importBackground(
            from: sourceURL,
            store: cleanupStore,
            settings: settings
        )
        expect(cleanupImportResult.didCommit)
        expect(cleanupImportResult.error?.localizedDescription
            == PanelBackgroundImportError.cleanupFailed.localizedDescription)
        expect(cleanupStore.asset?.id != cleanupPreviousID)
        expect(settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1)
        expect(settings.panelBackgroundPositionX == 0)
        expect(settings.panelBackgroundPositionY == 0)
        expect(settings.isPanelBackgroundAudioEnabled)

        let cleanupManifestData = try Data(
            contentsOf: cleanupDirectory.appendingPathComponent("manifest.json")
        )
        let cleanupManifest = try JSONDecoder().decode(
            PanelBackgroundManifest.self,
            from: cleanupManifestData
        )
        cleanupManager.blockedRemovalPath = cleanupDirectory
            .appendingPathComponent(cleanupManifest.mediaFilename)
            .standardizedFileURL.path
        settings.setPanelBackgroundEnabled(true)
        settings.setPanelBackgroundZoom(1.8)
        settings.setPanelBackgroundPosition(x: -0.6, y: 0.4)
        settings.setPanelBackgroundAudioEnabled(true)
        let cleanupResult = SettingsPanelBackgroundOperations.removeBackground(
            store: cleanupStore,
            settings: settings
        )
        expect(cleanupResult.didCommit)
        expect(cleanupResult.error?.localizedDescription
            == PanelBackgroundImportError.cleanupFailed.localizedDescription)
        expect(cleanupStore.asset == nil)
        expect(!settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1)
        expect(settings.panelBackgroundPositionX == 0)
        expect(settings.panelBackgroundPositionY == 0)
        expect(!settings.isPanelBackgroundAudioEnabled)

        try await verifyRollbackFailureAdoptsReplacement(
            in: fixtureRoot,
            sourceURL: sourceURL,
            settings: settings
        )
        try await verifyRollbackFailureClearsAuthority(
            in: fixtureRoot,
            sourceURL: sourceURL,
            settings: settings
        )
        try await verifyUnchangedRollbackFailurePreservesSettings(
            in: fixtureRoot,
            sourceURL: sourceURL,
            settings: settings
        )
    }

    @MainActor
    private static func verifyRollbackFailureAdoptsReplacement(
        in fixtureRoot: URL,
        sourceURL: URL,
        settings: MonitorSettings
    ) async throws {
        let directory = fixtureRoot.appendingPathComponent(
            "operation-rollback-adopts-replacement",
            isDirectory: true
        )
        let initialStore = PanelBackgroundStore(directoryURL: directory)
        try await initialStore.importBackground(from: sourceURL)
        let previousID = initialStore.asset?.id
        let fileManager = SettingsRollbackFaultFileManager()
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            prepareImport: makeVideoPreparation(sourceImageURL: sourceURL),
            writeManifest: fileManager.writeManifest
        )
        fileManager.hideCommittedPosterOnce = true
        fileManager.failManifestOperationNumbers = [2]
        settings.setPanelBackgroundEnabled(false)
        settings.setPanelBackgroundZoom(1.75)
        settings.setPanelBackgroundPosition(x: 0.55, y: -0.45)
        settings.setPanelBackgroundAudioEnabled(true)

        let result = await SettingsPanelBackgroundOperations.importBackground(
            from: sourceURL,
            store: store,
            settings: settings
        )

        expect(result.didCommit)
        guard let error = result.error as? PanelBackgroundImportError,
              case .rollbackFailed = error else {
            fatalError("Expected rollbackFailed after adopting replacement authority")
        }
        expect(store.asset?.id != previousID)
        expect(store.asset?.kind == .video)
        expect(settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1)
        expect(settings.panelBackgroundPositionX == 0)
        expect(settings.panelBackgroundPositionY == 0)
        expect(!settings.isPanelBackgroundAudioEnabled)
    }

    @MainActor
    private static func verifyRollbackFailureClearsAuthority(
        in fixtureRoot: URL,
        sourceURL: URL,
        settings: MonitorSettings
    ) async throws {
        let directory = fixtureRoot.appendingPathComponent(
            "operation-rollback-clears-authority",
            isDirectory: true
        )
        let initialStore = PanelBackgroundStore(directoryURL: directory)
        try await initialStore.importBackground(from: sourceURL)
        let fileManager = SettingsRollbackFaultFileManager()
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            writeManifest: fileManager.writeManifest
        )
        fileManager.corruptManifestOperationNumbers = [1]
        fileManager.failManifestOperationNumbers = [2]
        settings.setPanelBackgroundEnabled(true)
        settings.setPanelBackgroundZoom(1.6)
        settings.setPanelBackgroundPosition(x: -0.4, y: 0.65)
        settings.setPanelBackgroundAudioEnabled(true)

        let result = await SettingsPanelBackgroundOperations.importBackground(
            from: sourceURL,
            store: store,
            settings: settings
        )

        expect(result.didCommit)
        guard let error = result.error as? PanelBackgroundImportError,
              case .rollbackFailed = error else {
            fatalError("Expected rollbackFailed after clearing invalid authority")
        }
        expect(store.asset == nil)
        expect(!settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1)
        expect(settings.panelBackgroundPositionX == 0)
        expect(settings.panelBackgroundPositionY == 0)
        expect(!settings.isPanelBackgroundAudioEnabled)
    }

    @MainActor
    private static func verifyUnchangedRollbackFailurePreservesSettings(
        in fixtureRoot: URL,
        sourceURL: URL,
        settings: MonitorSettings
    ) async throws {
        let directory = fixtureRoot.appendingPathComponent(
            "operation-rollback-preserves-authority",
            isDirectory: true
        )
        let initialStore = PanelBackgroundStore(directoryURL: directory)
        try await initialStore.importBackground(from: sourceURL)
        let previousID = initialStore.asset?.id
        let fileManager = SettingsRollbackFaultFileManager()
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            prepareImport: makeVideoPreparation(sourceImageURL: sourceURL),
            writeManifest: fileManager.writeManifest
        )
        fileManager.failMoveDestinationPrefix = "poster-"
        fileManager.failRemoveDestinationPrefix = "media-"
        settings.setPanelBackgroundEnabled(false)
        settings.setPanelBackgroundZoom(1.7)
        settings.setPanelBackgroundPosition(x: 0.35, y: -0.75)
        settings.setPanelBackgroundAudioEnabled(true)

        let result = await SettingsPanelBackgroundOperations.importBackground(
            from: sourceURL,
            store: store,
            settings: settings
        )

        expect(!result.didCommit)
        guard let error = result.error as? PanelBackgroundImportError,
              case .rollbackFailed = error else {
            fatalError("Expected rollbackFailed with unchanged authority")
        }
        expect(store.asset?.id == previousID)
        expect(!settings.isPanelBackgroundEnabled)
        expect(settings.panelBackgroundZoom == 1.7)
        expect(settings.panelBackgroundPositionX == 0.35)
        expect(settings.panelBackgroundPositionY == -0.75)
        expect(settings.isPanelBackgroundAudioEnabled)
    }

    private static func makeVideoPreparation(
        sourceImageURL: URL
    ) -> PanelBackgroundPrepareImport {
        { _, stagingDirectory in
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            let mediaURL = stagingDirectory.appendingPathComponent("prepared.mov")
            let posterURL = stagingDirectory.appendingPathComponent("prepared-poster.png")
            try Data([0]).write(to: mediaURL)
            try FileManager.default.copyItem(at: sourceImageURL, to: posterURL)
            return PanelBackgroundPreparedImport(
                kind: .video,
                mediaURL: mediaURL,
                posterURL: posterURL,
                originalTypeIdentifier: "com.apple.quicktime-movie",
                hasAudio: true
            )
        }
    }

    @MainActor
    private static func verifyEmptyAndProcessingPresentation(
        settings: MonitorSettings,
        monitor: PerformanceMonitor,
        fixtureRoot: URL,
        outputDirectory: String
    ) throws {
        let emptyStore = PanelBackgroundStore(
            directoryURL: fixtureRoot.appendingPathComponent("empty", isDirectory: true)
        )
        let populatedStore = try makeFixtureStore(
            in: fixtureRoot,
            name: "populated-processing",
            kind: .staticImage,
            hasAudio: false
        )
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for size in [SettingsLayout.defaultContentSize, SettingsLayout.minimumContentSize] {
                let emptyReport = try render(
                    SettingsView(
                        settings: settings,
                        panelBackgroundStore: emptyStore,
                        monitor: monitor,
                        updateController: UpdateController()
                    ),
                    page: .appearance,
                    appearance: appearance,
                    size: size,
                    outputPath: outputDirectory
                        + "/fixture-empty-\(appearance.rawValue)-"
                        + "\(Int(size.width))x\(Int(size.height)).png"
                )
                expect(emptyReport.labels.contains("自定义背景"))
                expect(emptyReport.labels.contains("选择背景…"))
                expect(
                    emptyReport.labels.contains(
                        "支持图片、GIF、MP4、MOV、M4V 及系统视频"
                    )
                )

                let operationState = SettingsBackgroundOperationState(isProcessing: true)
                let processingReport = try render(
                    SettingsView(
                        settings: settings,
                        panelBackgroundStore: emptyStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        backgroundOperationState: operationState
                    ),
                    page: .appearance,
                    appearance: appearance,
                    size: size,
                    outputPath: outputDirectory
                        + "/fixture-processing-\(appearance.rawValue)-"
                        + "\(Int(size.width))x\(Int(size.height)).png"
                )
                expect(processingReport.labels.contains("正在处理动态背景…"))

                let populatedProcessingReport = try render(
                    SettingsView(
                        settings: settings,
                        panelBackgroundStore: populatedStore,
                        monitor: monitor,
                        updateController: UpdateController(),
                        backgroundOperationState: operationState
                    ),
                    page: .appearance,
                    appearance: appearance,
                    size: size,
                    outputPath: outputDirectory
                        + "/fixture-populated-processing-\(appearance.rawValue)-"
                        + "\(Int(size.width))x\(Int(size.height)).png",
                    expectedBackgroundTypeLabel: "静态图片",
                    expectsPreviewAudioToggle: false
                )
                expect(populatedProcessingReport.labels.contains("正在处理动态背景…"))
                expect(
                    populatedProcessingReport.controlEnabledStates[
                        "settings-background-replace"
                    ] == false
                )
                expect(
                    populatedProcessingReport.controlEnabledStates[
                        "settings-background-remove"
                    ] == false
                )
            }
        }
    }

    @MainActor
    private static func makeFixtureStore(
        in fixtureRoot: URL,
        name: String,
        kind: PanelBackgroundMediaKind,
        hasAudio: Bool
    ) throws -> PanelBackgroundStore {
        let directory = fixtureRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let generationID = "fixture-\(UUID().uuidString)"
        let mediaExtension = kind == .staticImage ? "png" : "mov"
        let mediaFilename = "media-\(generationID).\(mediaExtension)"
        let posterFilename = kind == .staticImage ? nil : "poster-\(generationID).png"
        let sourceImageURL = URL(fileURLWithPath: "Artwork/ColdHot-AppIcon-Pulse-Source.png")
        if kind == .staticImage {
            try FileManager.default.copyItem(
                at: sourceImageURL,
                to: directory.appendingPathComponent(mediaFilename)
            )
        } else {
            try Data([0x00]).write(to: directory.appendingPathComponent(mediaFilename))
            try FileManager.default.copyItem(
                at: sourceImageURL,
                to: directory.appendingPathComponent(posterFilename!)
            )
        }
        let manifest = PanelBackgroundManifest(
            schemaVersion: PanelBackgroundManifest.currentSchemaVersion,
            generationID: generationID,
            kind: kind,
            mediaFilename: mediaFilename,
            posterFilename: posterFilename,
            originalTypeIdentifier: kind == .staticImage ? "public.png" : "com.apple.quicktime-movie",
            hasAudio: hasAudio
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        return PanelBackgroundStore(directoryURL: directory)
    }

    @MainActor
    private static func makePreviewSession() -> SettingsPanelBackgroundPreviewSession {
        let dependencies = PanelBackgroundPlaybackDependencies(
            preparePlayerItem: { _ in throw CancellationError() },
            observePlayerItemStatus: { item, statusHandler in
                item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    let errorDescription = item.error?.localizedDescription
                    DispatchQueue.main.async {
                        statusHandler(status, errorDescription)
                    }
                }
            }
        )
        return SettingsPanelBackgroundPreviewSession(
            controller: PanelBackgroundPlaybackController(dependencies: dependencies)
        )
    }

    private static func backgroundTypeLabel(for kind: PanelBackgroundMediaKind) -> String {
        switch kind {
        case .staticImage: "静态图片"
        case .convertedGIF: "动态 GIF"
        case .video: "视频"
        }
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

    private static func brightPixelCount(
        inTopOriginRect rect: CGRect,
        bitmap: NSBitmapImageRep,
        logicalSize: CGSize
    ) -> Int {
        guard logicalSize.width > 0, logicalSize.height > 0 else { return 0 }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((rect.maxX * scaleX).rounded(.up)))
        let topY = max(0, Int((rect.minY * scaleY).rounded(.down)))
        let bottomY = min(bitmap.pixelsHigh, Int((rect.maxY * scaleY).rounded(.up)))
        var count = 0

        for topOriginY in topY..<bottomY {
            let bitmapY = bitmap.pixelsHigh - 1 - topOriginY
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: bitmapY)?.usingColorSpace(.deviceRGB)
                else { continue }
                if color.alphaComponent > 0.5,
                   color.redComponent > 0.65,
                   color.greenComponent > 0.65,
                   color.blueComponent > 0.65 {
                    count += 1
                }
            }
        }
        return count
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
private final class AccessibilityActionStore {
    var values: [String: () -> Void] = [:]
}

@MainActor
private final class SettingsControlEnabledStore {
    var values: [String: Bool] = [:]
}

private struct SettingsRenderReport {
    let identifiers: Set<String>
    let labels: Set<String>
    let actions: [String: () -> Void]
    let controlEnabledStates: [String: Bool]
}

@MainActor
private final class SettingsAsyncResultBox {
    var result: Result<Void, Error>?
}

private final class SettingsCleanupFailingFileManager: FileManager, @unchecked Sendable {
    var blockedRemovalPath: String?

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL.path == blockedRemovalPath {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

private final class SettingsRollbackFaultFileManager: FileManager, @unchecked Sendable {
    var failMoveDestinationPrefix: String?
    var failRemoveDestinationPrefix: String?
    var failManifestOperationNumbers: Set<Int> = []
    var corruptManifestOperationNumbers: Set<Int> = []
    var hideCommittedPosterOnce = false

    private var manifestOperationCount = 0
    private var didFailRemovePrefix = false

    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if let prefix = failMoveDestinationPrefix,
           destinationURL.lastPathComponent.hasPrefix(prefix) {
            throw SettingsInjectedStoreFailure.requested
        }
        try super.moveItem(at: sourceURL, to: destinationURL)
    }

    func writeManifest(_ data: Data, to url: URL) throws {
        manifestOperationCount += 1
        if failManifestOperationNumbers.contains(manifestOperationCount) {
            throw SettingsInjectedStoreFailure.requested
        }
        if corruptManifestOperationNumbers.contains(manifestOperationCount) {
            try Data("{ corrupt".utf8).write(to: url, options: .atomic)
            throw SettingsInjectedStoreFailure.requested
        }
        try data.write(to: url, options: .atomic)
    }

    override func removeItem(at URL: URL) throws {
        if let prefix = failRemoveDestinationPrefix,
           URL.lastPathComponent.hasPrefix(prefix),
           !didFailRemovePrefix {
            didFailRemovePrefix = true
            throw SettingsInjectedStoreFailure.requested
        }
        try super.removeItem(at: URL)
    }

    override func fileExists(atPath path: String) -> Bool {
        if hideCommittedPosterOnce,
           manifestOperationCount > 0,
           URL(fileURLWithPath: path).lastPathComponent.hasPrefix("poster-") {
            hideCommittedPosterOnce = false
            return false
        }
        return super.fileExists(atPath: path)
    }
}

private enum SettingsInjectedStoreFailure: Error {
    case requested
}

@MainActor
private final class SidebarSelectionStore {
    var value: SettingsPage = .appearance
}
