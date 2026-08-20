@preconcurrency import AVFoundation
import AppKit
import SwiftUI

struct PanelBackgroundPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PanelBackgroundPlayerLayerView {
        PanelBackgroundPlayerLayerView(player: player)
    }

    func updateNSView(_ nsView: PanelBackgroundPlayerLayerView, context: Context) {
        nsView.updatePlayer(player)
    }

    static func dismantleNSView(
        _ nsView: PanelBackgroundPlayerLayerView,
        coordinator: ()
    ) {
        nsView.updatePlayer(nil)
    }
}

final class PanelBackgroundPlayerLayerView: NSView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer?) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        wantsLayer = true
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updatePlayer(_ player: AVPlayer?) {
        guard playerLayer.player !== player else { return }
        playerLayer.player = player
    }
}
