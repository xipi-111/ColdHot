import Foundation

@main
enum PanelBackgroundCheck {
    static func main() throws {
        checkSettingsPersistence()
        print("Panel background checks passed")
    }

    private static func checkSettingsPersistence() {
        let suiteName = "com.xipiyoung.ColdHot.panel-background-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = MonitorSettings(defaults: defaults)
        expect(!initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundDimOpacity == 0.35)

        initial.setPanelBackgroundEnabled(true)
        initial.setPanelBackgroundDimOpacity(1)

        let restored = MonitorSettings(defaults: defaults)
        expect(restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.70)

        restored.setPanelBackgroundDimOpacity(-1)
        expect(restored.panelBackgroundDimOpacity == 0)

        restored.reset()
        expect(!restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.35)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Check failed", file: file, line: line)
        }
    }
}
