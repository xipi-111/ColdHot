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

private struct SettingsAccessibilityIdentifierReporterKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var settingsAccessibilityIdentifierReporter: ((String) -> Void)? {
        get { self[SettingsAccessibilityIdentifierReporterKey.self] }
        set { self[SettingsAccessibilityIdentifierReporterKey.self] = newValue }
    }
}

extension View {
    func settingsAccessibilityIdentifier(_ identifier: String) -> some View {
        modifier(SettingsAccessibilityIdentifierModifier(identifier: identifier))
    }
}

private struct SettingsAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String
    @Environment(\.settingsAccessibilityIdentifierReporter) private var reporter

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(identifier)
            .onAppear { reporter?(identifier) }
    }
}

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

struct LegacySidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
    }
}

struct SettingsSidebarRowStyle: ButtonStyle {
    let isSelected: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarRowStyleBody(
            configuration: configuration,
            isSelected: isSelected,
            isFocused: isFocused
        )
    }
}

private struct SettingsSidebarRowStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let isFocused: Bool

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHovering = false

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    private var backgroundOpacity: Double {
        if configuration.isPressed {
            return isWindowActive ? 0.13 : 0.085
        }
        if isSelected {
            return isWindowActive ? 0.085 : 0.055
        }
        if isHovering {
            return isWindowActive ? 0.055 : 0.035
        }
        return 0
    }

    var body: some View {
        configuration.label
            .foregroundStyle(
                isSelected
                    ? Color.green.opacity(isWindowActive ? 1 : 0.62)
                    : Color.primary.opacity(isWindowActive ? 1 : 0.68)
            )
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            Color.primary.opacity(isWindowActive ? 0.46 : 0.26),
                            lineWidth: 2
                        )
                }
            }
            .onHover { isHovering = $0 }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let versionText: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var focusedPage: SettingsPage?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 50)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarButton(for: page)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            Divider()

            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("ColdHot")
                        .font(.caption.weight(.medium))
                    Text(versionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .opacity(controlActiveState == .inactive ? 0.68 : 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: SettingsLayout.sidebarWidth)
        .background { material }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(controlActiveState == .inactive ? 0.055 : 0.085))
                .frame(width: 1)
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .settingsAccessibilityIdentifier("settings-sidebar")
    }

    @ViewBuilder
    private func sidebarButton(for page: SettingsPage) -> some View {
        let button = Button {
            selection = page
            focusedPage = page
        } label: {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .frame(width: 18)
                Text(page.rawValue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(
            SettingsSidebarRowStyle(
                isSelected: selection == page,
                isFocused: focusedPage == page
            )
        )
        .focused($focusedPage, equals: page)
        .accessibilityIdentifier("settings-sidebar-\(page.slug)")

        if selection == page {
            button.accessibilityAddTraits(.isSelected)
        } else {
            button
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let moveDirection: SettingsSidebarMoveDirection
        switch direction {
        case .up:
            moveDirection = .up
        case .down:
            moveDirection = .down
        default:
            return
        }

        let page = SettingsSidebarSelection.move(
            from: focusedPage ?? selection,
            direction: moveDirection
        )
        focusedPage = page
        selection = page
    }

    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.green.opacity(0.035)), in: Rectangle())
        } else {
            LegacySidebarMaterial()
        }
    }
}

struct SettingsShell<Content: View>: View {
    @Binding var selection: SettingsPage
    let versionText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: Content

    init(
        selection: Binding<SettingsPage>,
        versionText: String,
        @ViewBuilder content: () -> Content
    ) {
        _selection = selection
        self.versionText = versionText
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, versionText: versionText)
                .frame(width: SettingsLayout.sidebarWidth)
            ZStack(alignment: .topLeading) {
                content
                    .id(selection)
                    .transition(.opacity)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: selection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct SettingsPageContent<Content: View>: View {
    let page: SettingsPage
    private let content: Content

    init(page: SettingsPage, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.rawValue)
                .font(.system(size: 34, weight: .bold))
                .padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    content
                }
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, SettingsLayout.pageTopPadding)
        .padding(.horizontal, SettingsLayout.pageHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .settingsAccessibilityIdentifier("settings-page-\(page.slug)")
    }
}

struct SettingsSectionSurface<Content: View>: View {
    let title: String?
    let footer: String?
    let identifier: String
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: String? = nil,
        footer: String? = nil,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        identifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                surfaceColor,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .settingsAccessibilityIdentifier(identifier)
    }

    private var surfaceColor: Color {
        colorScheme == .dark
            ? Color.primary.opacity(0.045)
            : Color.white.opacity(0.64)
    }
}

struct SettingsRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsLayout.rowHeight,
                alignment: .leading
            )
            .padding(.horizontal, 14)
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.075))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}
