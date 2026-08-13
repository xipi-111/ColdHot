import AppKit
import Foundation
import Darwin

#if APP_STORE
final class DockDelayController: ObservableObject {
    @Published private(set) var isInstant = false
    @Published private(set) var isAutoHideEnabled = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    func setInstant(_ enabled: Bool) {}
    func refresh() {}
}
#else
final class DockDelayController: ObservableObject {
    @Published private(set) var isInstant = false
    @Published private(set) var isAutoHideEnabled = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    private let appDefaults: UserDefaults
    private let dockDomain = "com.apple.dock" as CFString
    private let delayKey = "autohide-delay" as CFString
    private let autoHideKey = "autohide" as CFString

    init(defaults: UserDefaults = .standard) {
        appDefaults = defaults
        refresh()
    }

    func setInstant(_ enabled: Bool) {
        guard enabled != isInstant, !isApplying else { return }
        isApplying = true
        errorMessage = nil

        if enabled {
            saveOriginalValueIfNeeded()
            setDockPreference(NSNumber(value: 0), key: delayKey)
        } else {
            restoreOriginalValue()
        }

        guard CFPreferencesAppSynchronize(dockDomain) else {
            errorMessage = "无法保存 Dock 设置"
            isApplying = false
            refresh()
            return
        }

        restartDock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isApplying = false
            self?.refresh()
        }
    }

    func refresh() {
        let delay = (CFPreferencesCopyAppValue(delayKey, dockDomain) as? NSNumber)?.doubleValue
        let autoHide = (CFPreferencesCopyAppValue(autoHideKey, dockDomain) as? NSNumber)?.boolValue ?? false
        isInstant = delay.map { abs($0) < 0.000_001 } ?? false
        isAutoHideEnabled = autoHide
    }

    private func saveOriginalValueIfNeeded() {
        guard !appDefaults.bool(forKey: Keys.backupExists) else { return }
        if let value = CFPreferencesCopyAppValue(delayKey, dockDomain) as? NSNumber {
            appDefaults.set(true, forKey: Keys.backupHadValue)
            appDefaults.set(value.doubleValue, forKey: Keys.backupValue)
        } else {
            appDefaults.set(false, forKey: Keys.backupHadValue)
        }
        appDefaults.set(true, forKey: Keys.backupExists)
    }

    private func restoreOriginalValue() {
        if appDefaults.bool(forKey: Keys.backupExists) {
            if appDefaults.bool(forKey: Keys.backupHadValue) {
                setDockPreference(NSNumber(value: appDefaults.double(forKey: Keys.backupValue)), key: delayKey)
            } else {
                setDockPreference(nil, key: delayKey)
            }
        } else {
            // 如果无备份但当前是零延迟，关闭代表回到 Apple 的默认延迟。
            setDockPreference(nil, key: delayKey)
        }
        appDefaults.removeObject(forKey: Keys.backupExists)
        appDefaults.removeObject(forKey: Keys.backupHadValue)
        appDefaults.removeObject(forKey: Keys.backupValue)
    }

    private func setDockPreference(_ value: CFPropertyList?, key: CFString) {
        CFPreferencesSetAppValue(key, value, dockDomain)
    }

    private func restartDock() {
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            if !application.terminate() {
                kill(application.processIdentifier, SIGTERM)
            }
        }
    }

    private enum Keys {
        static let backupExists = "dockDelayBackupExists"
        static let backupHadValue = "dockDelayBackupHadValue"
        static let backupValue = "dockDelayBackupValue"
    }
}
#endif
