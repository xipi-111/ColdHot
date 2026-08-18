import SwiftUI
import AppKit

private struct PanelCardOpacityKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct PanelPrimaryTextOpacityKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct PanelSecondaryTextOpacityKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct PanelProgressOpacityKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct PanelUsesCustomBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var panelCardOpacity: Double {
        get { self[PanelCardOpacityKey.self] }
        set { self[PanelCardOpacityKey.self] = newValue }
    }

    var panelPrimaryTextOpacity: Double {
        get { self[PanelPrimaryTextOpacityKey.self] }
        set { self[PanelPrimaryTextOpacityKey.self] = newValue }
    }

    var panelSecondaryTextOpacity: Double {
        get { self[PanelSecondaryTextOpacityKey.self] }
        set { self[PanelSecondaryTextOpacityKey.self] = newValue }
    }

    var panelProgressOpacity: Double {
        get { self[PanelProgressOpacityKey.self] }
        set { self[PanelProgressOpacityKey.self] = newValue }
    }

    var panelUsesCustomBackground: Bool {
        get { self[PanelUsesCustomBackgroundKey.self] }
        set { self[PanelUsesCustomBackgroundKey.self] = newValue }
    }
}

enum PanelTextRole {
    case primary
    case secondary
}

enum PanelLayout {
    static let width: CGFloat = 370
    static let minimumCollapsedMetricCount = 4
    static let maximumCollapsedMetricCount = 7
    static let maximumMetricsViewportHeight: CGFloat = 512

    private static let collapsedCardHeight: CGFloat = 62
    private static let cardSpacing: CGFloat = 8
    private static let verticalPadding: CGFloat = 24

    static func metricsViewportHeight(
        metricCount: Int,
        hasExpandedMetric: Bool
    ) -> CGFloat {
        if hasExpandedMetric {
            return maximumMetricsViewportHeight
        }

        let visibleCardCount = min(
            max(metricCount, minimumCollapsedMetricCount),
            maximumCollapsedMetricCount
        )
        if visibleCardCount == maximumCollapsedMetricCount {
            return maximumMetricsViewportHeight
        }

        let collapsedCards = CGFloat(visibleCardCount) * collapsedCardHeight
        let spacing = CGFloat(max(0, visibleCardCount - 1)) * cardSpacing
        return collapsedCards + spacing + verticalPadding
    }
}

enum PanelMetricVisibility {
    static func visibleMetrics<Metric: Hashable>(
        available: [Metric],
        userEnabled: Set<Metric>,
        activeAlertMetrics _: Set<Metric>
    ) -> [Metric] {
        available.filter(userEnabled.contains)
    }
}

enum PanelScrollBehavior {
    static func allowsScrolling<Metric>(expandedMetric: Metric?) -> Bool {
        expandedMetric != nil
    }
}

struct PanelExpansionDecision<Metric: Equatable> {
    let expandedMetric: Metric?
    let scrollTarget: Metric?
}

struct PanelExpansionAnimationPlan<Metric: Equatable> {
    let initialVisibleDetails: Metric?
    let layoutMetric: Metric?
    let layoutDelay: TimeInterval
    let layoutAnimationDuration: TimeInterval
    let finalVisibleDetails: Metric?
    let detailsDelay: TimeInterval
    let initialDetailsAnimationDuration: TimeInterval
    let finalDetailsAnimationDuration: TimeInterval
    let scrollTarget: Metric?
    let scrollDelay: TimeInterval
    let scrollAnimationDuration: TimeInterval

    static func transition(
        from current: Metric?,
        to target: Metric?,
        reduceMotion: Bool
    ) -> Self {
        guard !reduceMotion else {
            return Self(
                initialVisibleDetails: target,
                layoutMetric: target,
                layoutDelay: 0,
                layoutAnimationDuration: 0,
                finalVisibleDetails: target,
                detailsDelay: 0,
                initialDetailsAnimationDuration: 0,
                finalDetailsAnimationDuration: 0,
                scrollTarget: target,
                scrollDelay: 0,
                scrollAnimationDuration: 0
            )
        }

        if current == target {
            return Self(
                initialVisibleDetails: target,
                layoutMetric: target,
                layoutDelay: 0,
                layoutAnimationDuration: 0,
                finalVisibleDetails: target,
                detailsDelay: 0,
                initialDetailsAnimationDuration: 0,
                finalDetailsAnimationDuration: 0,
                scrollTarget: target,
                scrollDelay: 0,
                scrollAnimationDuration: 0
            )
        }

        let isCollapsing = target == nil
        let isSwitching = current != nil && target != nil
        let fadeOutDuration = current == nil ? 0 : (isSwitching ? 0.08 : 0.10)
        let layoutDelay = current == nil ? 0 : fadeOutDuration
        let layoutDuration = isSwitching ? 0.28 : (isCollapsing ? 0.24 : 0.26)
        let detailsDelay = target == nil ? 0 : layoutDelay + 0.06
        let scrollDelay = target == nil ? 0 : layoutDelay + layoutDuration

        return Self(
            initialVisibleDetails: nil,
            layoutMetric: target,
            layoutDelay: layoutDelay,
            layoutAnimationDuration: layoutDuration,
            finalVisibleDetails: target,
            detailsDelay: detailsDelay,
            initialDetailsAnimationDuration: fadeOutDuration,
            finalDetailsAnimationDuration: target == nil ? 0 : 0.16,
            scrollTarget: target,
            scrollDelay: scrollDelay,
            scrollAnimationDuration: target == nil ? 0 : 0.16
        )
    }
}

enum PanelExpansionBehavior {
    static func decision<Metric: Equatable>(
        toggling metric: Metric,
        current: Metric?
    ) -> PanelExpansionDecision<Metric> {
        guard current != metric else {
            return PanelExpansionDecision(expandedMetric: nil, scrollTarget: nil)
        }
        return PanelExpansionDecision(expandedMetric: metric, scrollTarget: metric)
    }
}

struct PanelBackgroundView: View {
    let image: NSImage?
    let isEnabled: Bool
    let dimOpacity: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            if isEnabled, let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()

                Color.black.opacity(min(max(dimOpacity, 0), 0.70))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PanelCardBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.panelCardOpacity) private var configuredOpacity
    @Environment(\.panelUsesCustomBackground) private var usesCustomBackground

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .opacity(usesCustomBackground ? min(max(configuredOpacity, 0.10), 1) : 1)
            .accessibilityHidden(true)
    }
}

private struct PanelTextReadabilityModifier: ViewModifier {
    let role: PanelTextRole

    @Environment(\.panelPrimaryTextOpacity) private var primaryOpacity
    @Environment(\.panelSecondaryTextOpacity) private var secondaryOpacity
    @Environment(\.panelUsesCustomBackground) private var usesCustomBackground

    func body(content: Content) -> some View {
        let configuredOpacity = role == .primary ? primaryOpacity : secondaryOpacity
        let opacity = usesCustomBackground ? min(max(configuredOpacity, 0.50), 1) : 1
        content
            .opacity(opacity)
            .shadow(
                color: usesCustomBackground ? .black.opacity(0.32) : .clear,
                radius: 0.75,
                x: 0,
                y: 0.5
            )
    }
}

private struct PanelProgressReadabilityModifier: ViewModifier {
    @Environment(\.panelProgressOpacity) private var configuredOpacity
    @Environment(\.panelUsesCustomBackground) private var usesCustomBackground

    func body(content: Content) -> some View {
        content.opacity(
            usesCustomBackground ? min(max(configuredOpacity, 0.50), 1) : 1
        )
    }
}

private struct PanelReadabilityEnvironmentModifier: ViewModifier {
    let cardOpacity: Double
    let primaryTextOpacity: Double
    let secondaryTextOpacity: Double
    let progressOpacity: Double
    let usesCustomBackground: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.panelCardOpacity, cardOpacity)
            .environment(\.panelPrimaryTextOpacity, primaryTextOpacity)
            .environment(\.panelSecondaryTextOpacity, secondaryTextOpacity)
            .environment(\.panelProgressOpacity, progressOpacity)
            .environment(\.panelUsesCustomBackground, usesCustomBackground)
    }
}

extension View {
    func hidePanelVerticalScrollIndicator(allowsScrolling: Bool = true) -> some View {
        background(PanelScrollViewConfigurator(allowsScrolling: allowsScrolling))
    }

    func panelTextReadability(_ role: PanelTextRole) -> some View {
        modifier(PanelTextReadabilityModifier(role: role))
    }

    func panelProgressReadability() -> some View {
        modifier(PanelProgressReadabilityModifier())
    }

    func panelReadability(
        cardOpacity: Double,
        primaryTextOpacity: Double,
        secondaryTextOpacity: Double,
        progressOpacity: Double,
        usesCustomBackground: Bool
    ) -> some View {
        modifier(PanelReadabilityEnvironmentModifier(
            cardOpacity: cardOpacity,
            primaryTextOpacity: primaryTextOpacity,
            secondaryTextOpacity: secondaryTextOpacity,
            progressOpacity: progressOpacity,
            usesCustomBackground: usesCustomBackground
        ))
    }
}

private struct PanelScrollViewConfigurator: NSViewRepresentable {
    let allowsScrolling: Bool

    func makeNSView(context: Context) -> PanelScrollConfigurationView {
        let view = PanelScrollConfigurationView()
        view.setAllowsScrolling(allowsScrolling)
        return view
    }

    func updateNSView(_ nsView: PanelScrollConfigurationView, context: Context) {
        nsView.setAllowsScrolling(allowsScrolling)
        nsView.configureEnclosingScrollView()
    }
}

private final class PanelScrollConfigurationView: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var scrollObservers: [NSObjectProtocol] = []
    private var allowsScrolling = true

    deinit {
        removeScrollObservers()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func setAllowsScrolling(_ allowsScrolling: Bool) {
        self.allowsScrolling = allowsScrolling
        if let configuredScrollView {
            applyConfiguration(to: configuredScrollView)
        }
    }

    func configureEnclosingScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let scrollView = self.findScrollView() else { return }
            self.configure(scrollView)
        }
    }

    private func findScrollView() -> NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            ancestor = view.superview
        }

        var root: NSView = self
        while let parent = root.superview {
            root = parent
        }
        let ownFrame = convert(bounds, to: root)
        let ownCenter = CGPoint(x: ownFrame.midX, y: ownFrame.midY)
        return descendantScrollViews(of: root)
            .filter { scrollView in
                scrollView.convert(scrollView.bounds, to: root).contains(ownCenter)
            }
            .min { left, right in
                let leftFrame = left.convert(left.bounds, to: root)
                let rightFrame = right.convert(right.bounds, to: root)
                let leftDifference = abs(leftFrame.width - ownFrame.width)
                    + abs(leftFrame.height - ownFrame.height)
                let rightDifference = abs(rightFrame.width - ownFrame.width)
                    + abs(rightFrame.height - ownFrame.height)
                return leftDifference < rightDifference
            }
    }

    private func descendantScrollViews(of view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview in
            let current = (subview as? NSScrollView).map { [$0] } ?? []
            return current + descendantScrollViews(of: subview)
        }
    }

    private func configure(_ scrollView: NSScrollView) {
        applyConfiguration(to: scrollView)

        guard configuredScrollView !== scrollView else { return }
        removeScrollObservers()
        configuredScrollView = scrollView

        let center = NotificationCenter.default
        let scrollNotifications: [Notification.Name] = [
            NSScrollView.willStartLiveScrollNotification,
            NSScrollView.didLiveScrollNotification,
            NSScrollView.didEndLiveScrollNotification
        ]
        scrollObservers = scrollNotifications.map { name in
            center.addObserver(
                forName: name,
                object: scrollView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView,
                      self.configuredScrollView === scrollView else { return }
                self.applyConfiguration(to: scrollView)
            }
        }

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObservers.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView,
                  self.configuredScrollView === scrollView else { return }
            self.applyConfiguration(to: scrollView)
        })
    }

    private func applyConfiguration(to scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        resetScrollPositionIfNeeded(in: scrollView)
    }

    private func resetScrollPositionIfNeeded(in scrollView: NSScrollView) {
        guard !allowsScrolling else { return }
        let currentOrigin = scrollView.contentView.bounds.origin
        let topY = scrollView.documentView?.bounds.minY ?? 0
        guard abs(currentOrigin.y - topY) >= 0.5 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: currentOrigin.x, y: topY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func removeScrollObservers() {
        let center = NotificationCenter.default
        scrollObservers.forEach(center.removeObserver)
        scrollObservers.removeAll()
    }
}
