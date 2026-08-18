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
        expect(SettingsPage.allCases.map(\.rawValue) == [
            "外观", "指标", "阈值提醒", "通用", "关于"
        ])
        expect(SettingsSidebarSelection.move(from: .appearance, direction: .up) == .about)
        expect(SettingsSidebarSelection.move(from: .about, direction: .down) == .appearance)
        expect(SettingsSidebarSelection.move(from: .metrics, direction: .down) == .alerts)

        let suiteName = "com.xipiyoung.ColdHot.settings-visual-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        settings.applyPreset(.everyday)
        settings.setPanelBackgroundEnabled(true)
        let monitor = PerformanceMonitor(settings: settings)
        let backgroundStore = PanelBackgroundStore()
        let view = SettingsView(
            settings: settings,
            panelBackgroundStore: backgroundStore,
            monitor: monitor,
            updateController: UpdateController()
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: SettingsLayout.defaultContentSize)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
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

        // SwiftUI can restore its standard title bar after the settings
        // window becomes key. The Apple Music-style treatment must persist.
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

        window.contentMinSize = .zero
        NotificationCenter.default.post(
            name: NSWindow.didResizeNotification,
            object: window
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(window.contentMinSize == SettingsLayout.minimumContentSize)

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create settings preview")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode settings preview")
        }

        let outputPath = CommandLine.arguments.dropFirst().first
            ?? "/tmp/coldhot-settings-preview.png"
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print(outputPath)
        if ProcessInfo.processInfo.environment["COLDHOT_SETTINGS_VISUAL_HOLD"] == "1" {
            RunLoop.main.run()
        }
    }

    @MainActor
    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { subview in
            [subview] + descendants(of: subview)
        }
    }
}
