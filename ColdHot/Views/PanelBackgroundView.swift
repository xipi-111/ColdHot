import SwiftUI
import AppKit

private struct PanelCardOpacityKey: EnvironmentKey {
    static let defaultValue = 1.0
}

private struct PanelTextOpacityKey: EnvironmentKey {
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

    var panelTextOpacity: Double {
        get { self[PanelTextOpacityKey.self] }
        set { self[PanelTextOpacityKey.self] = newValue }
    }

    var panelUsesCustomBackground: Bool {
        get { self[PanelUsesCustomBackgroundKey.self] }
        set { self[PanelUsesCustomBackgroundKey.self] = newValue }
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
    @Environment(\.panelTextOpacity) private var configuredOpacity
    @Environment(\.panelUsesCustomBackground) private var usesCustomBackground

    func body(content: Content) -> some View {
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

private struct PanelReadabilityEnvironmentModifier: ViewModifier {
    let cardOpacity: Double
    let textOpacity: Double
    let usesCustomBackground: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.panelCardOpacity, cardOpacity)
            .environment(\.panelTextOpacity, textOpacity)
            .environment(\.panelUsesCustomBackground, usesCustomBackground)
    }
}

extension View {
    func panelTextReadability() -> some View {
        modifier(PanelTextReadabilityModifier())
    }

    func panelReadability(
        cardOpacity: Double,
        textOpacity: Double,
        usesCustomBackground: Bool
    ) -> some View {
        modifier(PanelReadabilityEnvironmentModifier(
            cardOpacity: cardOpacity,
            textOpacity: textOpacity,
            usesCustomBackground: usesCustomBackground
        ))
    }
}
