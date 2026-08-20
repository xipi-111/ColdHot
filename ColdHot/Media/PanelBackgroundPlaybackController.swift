@preconcurrency import AVFoundation
import Combine
import Foundation

struct PanelBackgroundPlaybackIntent: Equatable {
    let isEnabled: Bool
    let isVisible: Bool
    let reduceMotion: Bool
    let audioRequested: Bool
    let assetIsDynamic: Bool
    let assetHasAudio: Bool

    var shouldPlay: Bool {
        isEnabled && isVisible && !reduceMotion && assetIsDynamic
    }

    var shouldMute: Bool {
        !shouldPlay || !assetHasAudio || !audioRequested
    }

    var shouldShowReduceMotionMessage: Bool {
        isEnabled && assetIsDynamic && reduceMotion
    }
}

@MainActor
struct PanelBackgroundPlaybackDependencies {
    typealias ItemStatusHandler = @MainActor (
        AVPlayerItem.Status,
        String?
    ) -> Void

    let preparePlayerItem: @MainActor (URL) async throws -> AVPlayerItem
    let observePlayerItemStatus: @MainActor (
        AVPlayerItem,
        @escaping ItemStatusHandler
    ) -> NSKeyValueObservation

    static var live: Self {
        Self(
            preparePlayerItem: { mediaURL in
                let asset = AVURLAsset(url: mediaURL)
                _ = try await asset.load(.duration)
                return AVPlayerItem(asset: asset)
            },
            observePlayerItemStatus: { item, statusHandler in
                item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    let errorDescription = item.error?.localizedDescription
                    DispatchQueue.main.async {
                        statusHandler(status, errorDescription)
                    }
                }
            }
        )
    }
}

@MainActor
final class PanelBackgroundPlaybackController: ObservableObject {
    let player: AVQueuePlayer

    @Published private(set) var activeAssetID: String?
    @Published private(set) var playbackErrorMessage: String?

    var hasActiveLooper: Bool { looper != nil }

    private var looper: AVPlayerLooper?
    private var preparationTask: Task<Void, Never>?
    private var looperStatusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var activeAsset: PanelBackgroundAsset?
    private var previousIntent: PanelBackgroundPlaybackIntent?
    private var hasPlaybackFailure = false
    private var didRetryCurrentAsset = false
    private var itemGeneration = 0
    private var itemObservationSequence = 0
    private let dependencies: PanelBackgroundPlaybackDependencies

    init(dependencies: PanelBackgroundPlaybackDependencies? = nil) {
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        self.dependencies = dependencies ?? .live
    }

    func configure(asset: PanelBackgroundAsset?) {
        guard activeAssetID != asset?.id else { return }

        clearPlayerItems()
        activeAsset = nil
        activeAssetID = nil
        hasPlaybackFailure = false
        didRetryCurrentAsset = false
        clearPlaybackError()

        guard let asset, asset.isDynamic, asset.mediaURL != nil else { return }
        activeAsset = asset
        activeAssetID = asset.id
        preparePlayerItem(for: asset)
    }

    func update(intent: PanelBackgroundPlaybackIntent) {
        let becameVisible = previousIntent?.isVisible == false && intent.isVisible
        previousIntent = intent

        player.isMuted = intent.shouldMute
        guard intent.shouldPlay else {
            player.pause()
            return
        }

        if hasPlaybackFailure {
            player.pause()
            if becameVisible && !didRetryCurrentAsset {
                didRetryCurrentAsset = true
                retryCurrentAsset(using: intent)
            }
            return
        }

        guard player.currentItem != nil else {
            player.pause()
            return
        }
        player.play()
    }

    func pause() {
        player.isMuted = true
        player.pause()
    }

    func reset() {
        clearPlayerItems()
        activeAsset = nil
        activeAssetID = nil
        previousIntent = nil
        hasPlaybackFailure = false
        didRetryCurrentAsset = false
        clearPlaybackError()
    }

    private func retryCurrentAsset(using intent: PanelBackgroundPlaybackIntent) {
        guard let activeAsset else { return }
        clearPlayerItems()
        hasPlaybackFailure = false
        preparePlayerItem(for: activeAsset)
        player.isMuted = intent.shouldMute
    }

    private func preparePlayerItem(for asset: PanelBackgroundAsset) {
        guard let mediaURL = asset.mediaURL else { return }

        itemGeneration += 1
        let generation = itemGeneration
        let preparePlayerItem = dependencies.preparePlayerItem
        preparationTask = Task { [weak self] in
            do {
                let templateItem = try await preparePlayerItem(mediaURL)
                try Task.checkCancellation()
                self?.installPlayerItem(templateItem, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                self?.handlePreparationFailure(error, generation: generation)
            }
        }
    }

    private func installPlayerItem(_ templateItem: AVPlayerItem, generation: Int) {
        guard generation == itemGeneration else { return }
        preparationTask = nil

        let looper = AVPlayerLooper(player: player, templateItem: templateItem)
        self.looper = looper

        looperStatusObservation = looper.observe(\.status, options: [.initial, .new]) {
            [weak self] looper, _ in
            let status = looper.status
            let errorDescription = looper.error?.localizedDescription
            DispatchQueue.main.async { [weak self] in
                self?.handleLooperStatus(
                    status,
                    errorDescription: errorDescription,
                    generation: generation
                )
            }
        }

        currentItemObservation = player.observe(
            \.currentItem,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            let item = player.currentItem
            DispatchQueue.main.async { [weak self] in
                self?.bindItemStatusObservation(to: item, generation: generation)
            }
        }

        guard player.currentItem != nil else {
            handlePlaybackFailure(errorDescription: nil, generation: generation)
            return
        }

        if let intent = previousIntent {
            player.isMuted = intent.shouldMute
            if intent.shouldPlay {
                player.play()
            }
        }
    }

    private func bindItemStatusObservation(
        to item: AVPlayerItem?,
        generation: Int
    ) {
        guard generation == itemGeneration else { return }
        if let item {
            guard player.currentItem === item else { return }
        } else {
            guard player.currentItem == nil else { return }
        }

        itemObservationSequence += 1
        let observationSequence = itemObservationSequence
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        guard let item else { return }

        itemStatusObservation = dependencies.observePlayerItemStatus(item) {
            [weak self] status, errorDescription in
            self?.handleItemStatus(
                status,
                errorDescription: errorDescription,
                generation: generation,
                observationSequence: observationSequence
            )
        }
    }

    private func handlePreparationFailure(_ error: Error, generation: Int) {
        guard generation == itemGeneration else { return }
        preparationTask = nil
        handlePlaybackFailure(
            errorDescription: error.localizedDescription,
            generation: generation
        )
    }

    private func handleLooperStatus(
        _ status: AVPlayerLooper.Status,
        errorDescription: String?,
        generation: Int
    ) {
        guard generation == itemGeneration else { return }
        if status == .failed {
            handlePlaybackFailure(
                errorDescription: errorDescription,
                generation: generation
            )
        }
    }

    private func handleItemStatus(
        _ status: AVPlayerItem.Status,
        errorDescription: String?,
        generation: Int,
        observationSequence: Int
    ) {
        guard generation == itemGeneration,
              observationSequence == itemObservationSequence else { return }

        switch status {
        case .readyToPlay:
            hasPlaybackFailure = false
            clearPlaybackError()
        case .failed:
            handlePlaybackFailure(
                errorDescription: errorDescription,
                generation: generation
            )
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlaybackFailure(errorDescription: String?, generation: Int) {
        guard generation == itemGeneration else { return }
        itemGeneration += 1
        player.pause()
        player.isMuted = true
        hasPlaybackFailure = true

        preparationTask?.cancel()
        preparationTask = nil
        looperStatusObservation?.invalidate()
        looperStatusObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        itemObservationSequence += 1
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()

        if playbackErrorMessage == nil {
            playbackErrorMessage = errorDescription ?? "无法播放动态背景。"
        }
    }

    private func clearPlayerItems() {
        itemGeneration += 1
        preparationTask?.cancel()
        preparationTask = nil
        looperStatusObservation?.invalidate()
        looperStatusObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        itemObservationSequence += 1
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.isMuted = true
        player.removeAllItems()
    }

    private func clearPlaybackError() {
        guard playbackErrorMessage != nil else { return }
        playbackErrorMessage = nil
    }
}
