import SwiftUI
import AppKit

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
