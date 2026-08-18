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

    static func metricsViewportHeight(
        metricCount: Int,
        hasExpandedMetric: Bool
    ) -> CGFloat {
        let count = max(metricCount, 0)
        let collapsed = CGFloat(count) * 62
        let spacing = CGFloat(max(0, count - 1)) * 8
        let expansion: CGFloat = hasExpandedMetric ? 300 : 0
        return min(max(collapsed + spacing + expansion + 24, 96), 500)
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
