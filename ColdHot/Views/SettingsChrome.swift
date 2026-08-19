import AppKit
import SwiftUI

enum SettingsLayout {
    static let defaultContentSize = CGSize(width: 920, height: 720)
    static let minimumContentSize = CGSize(width: 860, height: 680)
    static let sidebarWidth: CGFloat = 204
    static let sectionSpacing: CGFloat = 24
    static let standardRowHeight: CGFloat = 48
    static let sliderRowHeight: CGFloat = 64
    static let compactRowHeight: CGFloat = 40
    static let sectionCornerRadius: CGFloat = 14
    static let sidebarSelectionCornerRadius: CGFloat = 10

    static func pageMetrics(mainViewportSize: CGSize) -> SettingsPageMetrics {
        SettingsPageMetrics(
            horizontalPadding: interpolated(
                value: mainViewportSize.width,
                lowerBound: 656,
                upperBound: 716,
                lowerValue: 30,
                upperValue: 34
            ),
            topPadding: interpolated(
                value: mainViewportSize.height,
                lowerBound: 680,
                upperBound: 720,
                lowerValue: 42,
                upperValue: 48
            )
        )
    }

    static func interpolated(
        value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat,
        lowerValue: CGFloat,
        upperValue: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else { return lowerValue }
        let progress = min(1, max(0, (value - lowerBound) / (upperBound - lowerBound)))
        return lowerValue + (upperValue - lowerValue) * progress
    }
}

struct SettingsPageMetrics: Equatable {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
}

enum SettingsScrollbarGeometry {
    static let visibleThumbWidth: CGFloat = 4

    static func visibleThumbRect(in systemKnobRect: CGRect) -> CGRect {
        guard systemKnobRect.width.isFinite,
              systemKnobRect.height.isFinite,
              !systemKnobRect.isNull,
              !systemKnobRect.isInfinite else {
            return .zero
        }
        let width = min(max(systemKnobRect.width, 0), visibleThumbWidth)
        return CGRect(
            x: systemKnobRect.maxX - width,
            y: systemKnobRect.minY,
            width: width,
            height: max(systemKnobRect.height, 0)
        )
    }
}

final class SettingsThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        let thumbRect = SettingsScrollbarGeometry.visibleThumbRect(
            in: rect(for: .knob)
        )
        guard thumbRect.width > 0, thumbRect.height > 0 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark
            ? NSColor.white.withAlphaComponent(0.58)
            : NSColor.black.withAlphaComponent(0.42)
        color.setFill()
        NSBezierPath(
            roundedRect: thumbRect,
            xRadius: SettingsScrollbarGeometry.visibleThumbWidth / 2,
            yRadius: SettingsScrollbarGeometry.visibleThumbWidth / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

enum SettingsScrollbarConfiguration {
    static func apply(to scrollView: NSScrollView) {
        if !(scrollView.verticalScroller is SettingsThinScroller) {
            scrollView.verticalScroller = SettingsThinScroller()
        }
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller?.controlSize = .regular
        scrollView.verticalScroller?.needsDisplay = true
        scrollView.tile()
    }
}

private struct SettingsScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsScrollViewProbe {
        SettingsScrollViewProbe()
    }

    func updateNSView(_ nsView: SettingsScrollViewProbe, context: Context) {
        nsView.configureEnclosingScrollViewWhenReady()
    }
}

private final class SettingsScrollViewProbe: NSView {
    private var isConfigurationScheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollViewWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollViewWhenReady()
    }

    func configureEnclosingScrollViewWhenReady() {
        guard !isConfigurationScheduled else { return }
        isConfigurationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConfigurationScheduled = false
            self.configureEnclosingScrollView()
        }
    }

    private func configureEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        SettingsScrollbarConfiguration.apply(to: scrollView)
    }
}

enum SettingsAppearanceColumnRole: Equatable {
    case preview
    case controls
}

struct SettingsAppearanceColumns: Equatable {
    let order: [SettingsAppearanceColumnRole]
    let previewWidth: CGFloat
    let controlsWidth: CGFloat
    let spacing: CGFloat
    let sliderRowHeight: CGFloat
    let previewHeight: CGFloat

    static func resolve(contentWidth: CGFloat) -> SettingsAppearanceColumns {
        let spacing = SettingsLayout.interpolated(
            value: contentWidth,
            lowerBound: 596,
            upperBound: 648,
            lowerValue: 16,
            upperValue: 20
        )
        let controlsWidth = SettingsLayout.interpolated(
            value: contentWidth,
            lowerBound: 596,
            upperBound: 648,
            lowerValue: 276,
            upperValue: 300
        )
        let sliderRowHeight = SettingsLayout.interpolated(
            value: contentWidth,
            lowerBound: 596,
            upperBound: 648,
            lowerValue: 56,
            upperValue: SettingsLayout.sliderRowHeight
        )
        let previewHeight = SettingsLayout.interpolated(
            value: contentWidth,
            lowerBound: 596,
            upperBound: 648,
            lowerValue: 488,
            upperValue: 520
        )
        return SettingsAppearanceColumns(
            order: [.preview, .controls],
            previewWidth: max(0, contentWidth - spacing - controlsWidth),
            controlsWidth: controlsWidth,
            spacing: spacing,
            sliderRowHeight: sliderRowHeight,
            previewHeight: previewHeight
        )
    }
}

enum SettingsPreviewScale {
    static func factor(contentWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard contentWidth > 0 else { return 1 }
        return min(1, max(0, availableWidth / contentWidth))
    }

    static func factor(contentSize: CGSize, availableSize: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        return min(
            1,
            max(
                0,
                min(
                    availableSize.width / contentSize.width,
                    availableSize.height / contentSize.height
                )
            )
        )
    }
}

private struct SettingsPreviewLogicalSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextSize = nextValue()
        if nextSize != .zero {
            value = nextSize
        }
    }
}

private struct SettingsPreviewAvailableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScaledSettingsPreview<Content: View>: View {
    @State private var logicalSize = CGSize.zero
    @State private var availableWidth: CGFloat = 0
    private let content: Content
    private let maximumHeight: CGFloat?

    init(maximumHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.maximumHeight = maximumHeight
        self.content = content()
    }

    private var scale: CGFloat {
        if let maximumHeight {
            SettingsPreviewScale.factor(
                contentSize: logicalSize,
                availableSize: CGSize(width: availableWidth, height: maximumHeight)
            )
        } else {
            SettingsPreviewScale.factor(
                contentWidth: logicalSize.width,
                availableWidth: availableWidth
            )
        }
    }

    private var presentedSize: CGSize {
        CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.clear.preference(
                    key: SettingsPreviewAvailableWidthKey.self,
                    value: proxy.size.width
                )

                content
                    .fixedSize()
                    .background {
                        GeometryReader { contentProxy in
                            Color.clear.preference(
                                key: SettingsPreviewLogicalSizeKey.self,
                                value: contentProxy.size
                            )
                        }
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: logicalSize == .zero ? nil : presentedSize.width,
                        height: logicalSize == .zero ? nil : presentedSize.height,
                        alignment: .topLeading
                    )
            }
        }
        .frame(
            width: logicalSize == .zero ? nil : presentedSize.width,
            height: logicalSize == .zero ? nil : presentedSize.height
        )
        .onPreferenceChange(SettingsPreviewLogicalSizeKey.self) { logicalSize = $0 }
        .onPreferenceChange(SettingsPreviewAvailableWidthKey.self) { availableWidth = $0 }
    }
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

    var requiresScrolling: Bool {
        self == .metrics || self == .alerts
    }
}

enum SettingsSidebarMoveDirection { case up, down }

private struct SettingsAccessibilityIdentifierReporterKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

private struct SettingsAccessibilityLabelReporterKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var settingsAccessibilityIdentifierReporter: ((String) -> Void)? {
        get { self[SettingsAccessibilityIdentifierReporterKey.self] }
        set { self[SettingsAccessibilityIdentifierReporterKey.self] = newValue }
    }

    var settingsAccessibilityLabelReporter: ((String) -> Void)? {
        get { self[SettingsAccessibilityLabelReporterKey.self] }
        set { self[SettingsAccessibilityLabelReporterKey.self] = newValue }
    }
}

extension View {
    func settingsAccessibilityIdentifier(_ identifier: String) -> some View {
        modifier(SettingsAccessibilityIdentifierModifier(identifier: identifier))
    }

    func settingsAccessibilityLabel(_ label: String) -> some View {
        modifier(SettingsAccessibilityLabelModifier(label: label))
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

private struct SettingsAccessibilityLabelModifier: ViewModifier {
    let label: String
    @Environment(\.settingsAccessibilityLabelReporter) private var reporter

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(Text(label))
            .onAppear { reporter?(label) }
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
                in: RoundedRectangle(
                    cornerRadius: SettingsLayout.sidebarSelectionCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(
                        cornerRadius: SettingsLayout.sidebarSelectionCornerRadius,
                        style: .continuous
                    )
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

            VStack(spacing: 4) {
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
        GeometryReader { proxy in
            let metrics = SettingsLayout.pageMetrics(mainViewportSize: proxy.size)

            pageBody(metrics: metrics)
            .padding(.top, metrics.topPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .settingsAccessibilityLabel(page.rawValue)
        .settingsAccessibilityIdentifier("settings-page-\(page.slug)")
    }

    @ViewBuilder
    private func pageBody(metrics: SettingsPageMetrics) -> some View {
        if page.requiresScrolling {
            ScrollView {
                contentStack
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, 32)
                    .background(SettingsScrollViewConfigurator())
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            contentStack
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            content
        }
        .frame(maxWidth: 660, alignment: .leading)
    }
}

struct SettingsSectionSurface<Content: View>: View {
    let title: String?
    let footer: String?
    let identifier: String
    private let headerAccessory: AnyView?
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
        headerAccessory = nil
        self.content = content()
    }

    init<HeaderAccessory: View>(
        _ title: String? = nil,
        footer: String? = nil,
        accessibilityIdentifier: String,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        identifier = accessibilityIdentifier
        self.headerAccessory = AnyView(
            headerAccessory()
                .settingsAccessibilityIdentifier(
                    "\(accessibilityIdentifier)-header-action"
                )
        )
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    headerAccessory
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                surfaceColor,
                in: RoundedRectangle(
                    cornerRadius: SettingsLayout.sectionCornerRadius,
                    style: .continuous
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: SettingsLayout.sectionCornerRadius,
                    style: .continuous
                )
            )

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
    let minHeight: CGFloat
    private let content: Content

    init(
        minHeight: CGFloat = SettingsLayout.standardRowHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                minHeight: minHeight,
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
