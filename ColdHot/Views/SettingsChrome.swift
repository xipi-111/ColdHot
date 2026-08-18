import AppKit
import SwiftUI

enum SettingsLayout {
    static let defaultContentSize = CGSize(width: 920, height: 720)
    static let minimumContentSize = CGSize(width: 860, height: 680)
    static let sidebarWidth: CGFloat = 204
    static let pageHorizontalPadding: CGFloat = 34
    static let pageTopPadding: CGFloat = 48
    static let sectionSpacing: CGFloat = 24
    static let rowHeight: CGFloat = 40
}

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case appearance = "外观"
    case metrics = "指标"
    case alerts = "阈值提醒"
    case general = "通用"
    case about = "关于"

    var id: Self { self }

    var slug: String {
        switch self {
        case .appearance: "appearance"
        case .metrics: "metrics"
        case .alerts: "alerts"
        case .general: "general"
        case .about: "about"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .metrics: "gauge.with.dots.needle.50percent"
        case .alerts: "exclamationmark.triangle"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

enum SettingsSidebarMoveDirection { case up, down }

enum SettingsSidebarSelection {
    static func move(
        from current: SettingsPage,
        direction: SettingsSidebarMoveDirection
    ) -> SettingsPage {
        let pages = SettingsPage.allCases
        guard let index = pages.firstIndex(of: current) else { return .appearance }
        switch direction {
        case .up: return pages[(index - 1 + pages.count) % pages.count]
        case .down: return pages[(index + 1) % pages.count]
        }
    }
}
