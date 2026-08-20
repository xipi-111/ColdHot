import Foundation

@main
enum DynamicBackgroundPolicyCheck {
    static func main() {
        checkImportLimits()
        checkMenuAudioPersistence()
        print("Dynamic background policy checks passed")
    }

    private static func checkImportLimits() {
        expect(PanelBackgroundImportLimits.maximumGIFBytes == 100 * 1_024 * 1_024)
        expect(PanelBackgroundImportLimits.maximumVideoBytes == 1_024 * 1_024 * 1_024)
        expect(PanelBackgroundImportLimits.acceptsGIF(byteCount: 100 * 1_024 * 1_024))
        expect(!PanelBackgroundImportLimits.acceptsGIF(byteCount: 100 * 1_024 * 1_024 + 1))
        expect(PanelBackgroundImportLimits.acceptsVideo(byteCount: 1_024 * 1_024 * 1_024))
        expect(!PanelBackgroundImportLimits.acceptsVideo(byteCount: 1_024 * 1_024 * 1_024 + 1))
    }

    private static func checkMenuAudioPersistence() {
        let suiteName = "com.xipiyoung.ColdHot.dynamic-background-policy-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = MonitorSettings(defaults: defaults)
        expect(!settings.isPanelBackgroundAudioEnabled)
        settings.setPanelBackgroundAudioEnabled(true)
        expect(MonitorSettings(defaults: defaults).isPanelBackgroundAudioEnabled)
        settings.didReplacePanelBackground(kind: .staticImage)
        expect(settings.isPanelBackgroundAudioEnabled)
        settings.didReplacePanelBackground(kind: .video)
        expect(!settings.isPanelBackgroundAudioEnabled)
        settings.setPanelBackgroundAudioEnabled(true)
        settings.didReplacePanelBackground(kind: .convertedGIF)
        expect(settings.isPanelBackgroundAudioEnabled)
        settings.didRemovePanelBackground()
        expect(!settings.isPanelBackgroundAudioEnabled)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else { fatalError("Check failed", file: file, line: line) }
    }
}
