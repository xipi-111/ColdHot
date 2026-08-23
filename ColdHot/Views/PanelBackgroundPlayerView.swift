@preconcurrency import AVFoundation
import AppKit
import SwiftUI

struct PanelBackgroundPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: (Bool) -> Void

    func makeNSView(context: Context) -> PanelBackgroundPlayerLayerView {
        PanelBackgroundPlayerLayerView(
            player: player,
            onReadyForDisplay: onReadyForDisplay
        )
    }

    func updateNSView(_ nsView: PanelBackgroundPlayerLayerView, context: Context) {
        nsView.update(
            player: player,
            onReadyForDisplay: onReadyForDisplay
        )
    }

    static func dismantleNSView(
        _ nsView: PanelBackgroundPlayerLayerView,
        coordinator: ()
    ) {
        nsView.update(player: nil, onReadyForDisplay: nil)
    }
}

final class PanelBackgroundPlayerLayerView: NSView {
    let playerLayer: AVPlayerLayer
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var onReadyForDisplay: ((Bool) -> Void)?

    init(
        player: AVPlayer?,
        onReadyForDisplay: @escaping (Bool) -> Void
    ) {
        playerLayer = AVPlayerLayer(player: player)
        self.onReadyForDisplay = onReadyForDisplay
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        wantsLayer = true
        layer = playerLayer
        readyForDisplayObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] layer, _ in
            let isReady = layer.isReadyForDisplay
            DispatchQueue.main.async { [weak self] in
                self?.onReadyForDisplay?(isReady)
            }
        }
    }

    convenience init(player: AVPlayer?) {
        self.init(player: player, onReadyForDisplay: { _ in })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        player: AVPlayer?,
        onReadyForDisplay: ((Bool) -> Void)?
    ) {
        self.onReadyForDisplay = onReadyForDisplay
        guard playerLayer.player !== player else { return }
        playerLayer.player = player
        DispatchQueue.main.async { [weak self] in
            self?.onReadyForDisplay?(false)
        }
    }

    func updatePlayer(_ player: AVPlayer?) {
        update(player: player, onReadyForDisplay: onReadyForDisplay)
    }
}
