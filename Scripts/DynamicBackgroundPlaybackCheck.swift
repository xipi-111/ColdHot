@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation

@main
enum DynamicBackgroundPlaybackCheck {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        checkPlaybackIntentPolicy()

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "ColdHotDynamicBackgroundPlaybackCheck-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let videoURL = directory.appendingPathComponent("two-seconds.mp4")
        try await makeTwoSecondVideo(at: videoURL, in: directory)
        try await checkPlaybackLifecycle(videoURL: videoURL)
        try await checkBoundedFailureLifecycle(in: directory)
        checkPlayerLayerBehavior()

        print("Dynamic background playback checks passed")
    }

    private static func checkPlaybackIntentPolicy() {
        let active = PanelBackgroundPlaybackIntent(
            isEnabled: true,
            isVisible: true,
            reduceMotion: false,
            audioRequested: true,
            assetIsDynamic: true,
            assetHasAudio: true
        )
        expect(active.shouldPlay, "An enabled visible dynamic asset must play")
        expect(!active.shouldMute, "Requested audio must be audible while playing")

        let hidden = active.copy(isVisible: false)
        expect(!hidden.shouldPlay, "A hidden dynamic asset must pause")
        expect(hidden.shouldMute, "A hidden dynamic asset must be muted")

        let reduced = active.copy(reduceMotion: true)
        expect(!reduced.shouldPlay, "Reduce Motion must pause dynamic media")
        expect(reduced.shouldMute, "Reduce Motion must mute dynamic media")
        expect(
            reduced.shouldShowReduceMotionMessage,
            "Reduce Motion must publish the explanatory-message policy"
        )

        let staticAsset = active.copy(assetIsDynamic: false)
        expect(!staticAsset.shouldPlay, "Static assets must never enter playback")
        expect(staticAsset.shouldMute, "Static assets must never emit audio")

        let silent = active.copy(assetHasAudio: false)
        expect(silent.shouldPlay, "Silent dynamic assets must still play")
        expect(silent.shouldMute, "Silent dynamic assets must remain muted")

        let audioDisabled = active.copy(audioRequested: false)
        expect(audioDisabled.shouldPlay, "Disabling audio must not stop video")
        expect(audioDisabled.shouldMute, "Disabling audio must mute video")
    }

    @MainActor
    private static func checkPlaybackLifecycle(videoURL: URL) async throws {
        let controller = PanelBackgroundPlaybackController()
        let firstAsset = dynamicAsset(id: "first", mediaURL: videoURL, hasAudio: true)
        let secondAsset = dynamicAsset(id: "second", mediaURL: videoURL, hasAudio: true)
        let active = PanelBackgroundPlaybackIntent(
            isEnabled: true,
            isVisible: true,
            reduceMotion: false,
            audioRequested: true,
            assetIsDynamic: true,
            assetHasAudio: true
        )

        var stateEvents: [PlaybackStateEvent] = []
        let muteObservation = controller.player.observe(\.isMuted, options: [.new]) {
            player, _ in
            stateEvents.append(player.isMuted ? .muted : .unmuted)
        }
        let rateObservation = controller.player.observe(\.rate, options: [.new]) {
            player, _ in
            if player.rate > 0 {
                stateEvents.append(.playing)
            }
        }
        defer {
            muteObservation.invalidate()
            rateObservation.invalidate()
        }

        controller.configure(asset: firstAsset)
        controller.update(intent: active)
        try await wait(
            until: { controller.player.currentItem != nil && controller.player.rate > 0 },
            timeout: 3,
            diagnostic: "Real video never began playing"
        )
        guard let firstItem = controller.player.currentItem else {
            throw CheckFailure("Configuring and playing a dynamic asset must install a player item")
        }
        controller.configure(asset: firstAsset)
        expect(
            controller.player.currentItem === firstItem,
            "Configuring the same asset ID must not recreate its item"
        )
        guard let unmutedIndex = stateEvents.firstIndex(of: .unmuted),
              let playingIndex = stateEvents.firstIndex(of: .playing) else {
            throw CheckFailure("Playback must publish unmuted and playing state changes")
        }
        expect(
            unmutedIndex < playingIndex,
            "The controller must apply mute state before starting playback"
        )

        try await wait(
            until: { controller.player.currentTime().seconds > 0.15 },
            timeout: 3,
            diagnostic: "Real video time did not advance"
        )
        let beforeHide = controller.player.currentTime().seconds
        controller.update(intent: active.copy(isVisible: false))
        expect(controller.player.rate == 0, "Hiding must synchronously pause playback")
        expect(controller.player.isMuted, "Hiding must synchronously mute playback")
        try await pauseFor(0.30)
        let hiddenTime = controller.player.currentTime().seconds
        expect(
            abs(hiddenTime - beforeHide) < 0.05,
            "Hidden playback advanced \(abs(hiddenTime - beforeHide)) seconds; expected under 0.05"
        )

        controller.update(intent: active)
        try await wait(
            until: { controller.player.currentTime().seconds > hiddenTime + 0.10 },
            timeout: 3,
            diagnostic: "Visible playback did not resume from its paused position"
        )
        expect(
            controller.player.currentTime().seconds > hiddenTime,
            "Visibility resume must continue without seeking to zero"
        )

        let itemBeforeReplacement = controller.player.currentItem
        controller.configure(asset: secondAsset)
        expect(controller.activeAssetID == secondAsset.id, "Replacement must publish the new ID")
        expect(
            controller.player.currentItem !== itemBeforeReplacement,
            "A changed asset ID must replace its player item"
        )
        expect(
            controller.player.currentItem == nil,
            "Replacement preparation must remove the previous item immediately"
        )
        controller.update(intent: active)
        try await wait(
            until: {
                let time = controller.player.currentTime().seconds
                return controller.player.currentItem != nil && time > 0.05 && time < 0.50
            },
            timeout: 3,
            diagnostic: "Replacement did not start near zero"
        )

        controller.pause()
        let pausedTime = controller.player.currentTime().seconds
        try await pauseFor(0.20)
        expect(controller.player.rate == 0, "Explicit pause must stop playback")
        expect(
            abs(controller.player.currentTime().seconds - pausedTime) < 0.05,
            "Explicit pause must not seek"
        )

        controller.reset()
        expect(controller.player.currentItem == nil, "Reset must remove the current item")
        expect(controller.player.items().isEmpty, "Reset must empty the player queue")
        expect(!controller.hasActiveLooper, "Reset must release the looper")
        expect(controller.activeAssetID == nil, "Reset must clear the active asset ID")
        expect(controller.playbackErrorMessage == nil, "Reset must clear playback errors")
    }

    @MainActor
    private static func checkBoundedFailureLifecycle(in directory: URL) async throws {
        let validVideoURL = directory.appendingPathComponent("two-seconds.mp4")
        let visible = PanelBackgroundPlaybackIntent(
            isEnabled: true,
            isVisible: true,
            reduceMotion: false,
            audioRequested: true,
            assetIsDynamic: true,
            assetHasAudio: true
        )

        let recoveryController = PanelBackgroundPlaybackController()
        let recoverableURL = directory.appendingPathComponent("recoverable-video.mp4")
        let recoverableAsset = dynamicAsset(
            id: "recoverable",
            mediaURL: recoverableURL,
            hasAudio: true
        )
        var publishedErrors: [String] = []
        let errorSubscription = recoveryController.$playbackErrorMessage
            .compactMap { $0 }
            .sink { publishedErrors.append($0) }
        defer { errorSubscription.cancel() }

        recoveryController.configure(asset: recoverableAsset)
        recoveryController.update(intent: visible)
        try await wait(
            until: { recoveryController.playbackErrorMessage != nil },
            timeout: 5,
            diagnostic: "Invalid media did not publish a playback error"
        )
        expect(recoveryController.player.rate == 0, "A failed item must be paused")
        expect(recoveryController.player.isMuted, "A failed item must be muted")
        expect(publishedErrors.count == 1, "Initial failure must publish exactly one error")
        expect(recoveryController.player.currentItem == nil, "A failed load must retain only its poster")
        try await pauseFor(0.50)
        expect(
            recoveryController.player.currentItem == nil,
            "A failure must not continuously recreate its item"
        )
        expect(publishedErrors.count == 1, "A failure must not continuously republish errors")

        try FileManager.default.copyItem(at: validVideoURL, to: recoverableURL)
        recoveryController.update(intent: visible.copy(isVisible: false))
        recoveryController.update(intent: visible)
        try await wait(
            until: {
                recoveryController.player.currentItem?.status == .readyToPlay
                    && recoveryController.player.currentTime().seconds > 0.05
            },
            timeout: 5,
            diagnostic: "The first hidden-to-visible transition did not retry recovered media"
        )
        expect(
            recoveryController.playbackErrorMessage == nil,
            "A successful retry must clear the poster-fallback error"
        )
        expect(publishedErrors.count == 1, "Recovery must retain one historical error publication")
        recoveryController.reset()

        let boundedController = PanelBackgroundPlaybackController()
        let boundedURL = directory.appendingPathComponent("bounded-missing-video.mp4")
        let boundedAsset = dynamicAsset(
            id: "bounded-invalid",
            mediaURL: boundedURL,
            hasAudio: true
        )
        var boundedErrors: [String] = []
        let boundedSubscription = boundedController.$playbackErrorMessage
            .compactMap { $0 }
            .sink { boundedErrors.append($0) }
        defer { boundedSubscription.cancel() }

        boundedController.configure(asset: boundedAsset)
        boundedController.update(intent: visible)
        try await wait(
            until: { boundedController.playbackErrorMessage != nil },
            timeout: 5,
            diagnostic: "Bounded-retry fixture did not fail initially"
        )
        boundedController.update(intent: visible.copy(isVisible: false))
        boundedController.update(intent: visible)
        try await pauseFor(0.50)
        expect(boundedController.player.currentItem == nil, "The one retry must remain failed")

        try FileManager.default.copyItem(at: validVideoURL, to: boundedURL)
        boundedController.update(intent: visible.copy(isVisible: false))
        boundedController.update(intent: visible)
        try await pauseFor(0.50)
        expect(
            boundedController.player.currentItem == nil,
            "A second hidden-to-visible transition must not retry again"
        )
        expect(boundedErrors.count == 1, "Bounded retry must not republish the same error")

        let replacement = dynamicAsset(
            id: "replacement",
            mediaURL: directory.appendingPathComponent("also-missing.mp4"),
            hasAudio: false
        )
        boundedController.configure(asset: replacement)
        expect(
            boundedController.playbackErrorMessage == nil,
            "Changing assets must clear the prior error state"
        )
        boundedController.reset()
    }

    @MainActor
    private static func checkPlayerLayerBehavior() {
        let firstPlayer = AVQueuePlayer()
        let secondPlayer = AVQueuePlayer()
        let view = PanelBackgroundPlayerLayerView(player: firstPlayer)

        expect(view.wantsLayer, "The player view must be layer-backed")
        expect(view.playerLayer.player === firstPlayer, "The player layer must retain player identity")
        expect(
            view.playerLayer.videoGravity == .resizeAspectFill,
            "The player layer must aspect-fill its shared crop frame"
        )
        expect(view.hitTest(.zero) == nil, "The background player must never receive input")

        view.updatePlayer(firstPlayer)
        expect(view.playerLayer.player === firstPlayer, "An identical update must preserve the player")
        view.updatePlayer(secondPlayer)
        expect(view.playerLayer.player === secondPlayer, "A replacement update must install the new player")
        view.updatePlayer(nil)
        expect(view.playerLayer.player == nil, "Dismantling must clear the player")
    }

    private static func dynamicAsset(
        id: String,
        mediaURL: URL,
        hasAudio: Bool
    ) -> PanelBackgroundAsset {
        PanelBackgroundAsset(
            id: id,
            kind: .video,
            posterImage: NSImage(size: NSSize(width: 32, height: 24)),
            mediaURL: mediaURL,
            hasAudio: hasAudio
        )
    }

    private static func makeTwoSecondVideo(at outputURL: URL, in directory: URL) async throws {
        let oneSecondURL = directory.appendingPathComponent("one-second.mp4")
        try await DynamicBackgroundTestMedia.makeSilentH264Video(at: oneSecondURL)

        let sourceAsset = AVURLAsset(url: oneSecondURL)
        guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw CheckFailure("Unable to load the generated video track")
        }
        let sourceDuration = try await sourceAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let destinationTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CheckFailure("Unable to create the two-second video track")
        }
        let range = CMTimeRange(start: .zero, duration: sourceDuration)
        try destinationTrack.insertTimeRange(range, of: sourceTrack, at: .zero)
        try destinationTrack.insertTimeRange(range, of: sourceTrack, at: sourceDuration)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw CheckFailure("Unable to create the two-second video exporter")
        }
        exporter.shouldOptimizeForNetworkUse = false
        if #available(macOS 15.0, *) {
            try await exporter.export(to: outputURL, as: .mp4)
        } else {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            await exporter.export()
            guard exporter.status == .completed else {
                throw CheckFailure(
                    "Two-second video export failed: \(exporter.error?.localizedDescription ?? "unknown")"
                )
            }
        }

        let result = AVURLAsset(url: outputURL)
        let duration = try await result.load(.duration).seconds
        let isPlayable = try await result.load(.isPlayable)
        let tracks = try await result.loadTracks(withMediaType: .video)
        expect(isPlayable, "Playback fixture must be playable")
        expect(tracks.count == 1, "Playback fixture must have exactly one video track")
        expect(
            abs(duration - 2) < 0.08,
            "Playback fixture must be a real two-second video; got \(duration) seconds"
        )
    }

    @MainActor
    private static func wait(
        until condition: () -> Bool,
        timeout: TimeInterval,
        diagnostic: @autoclosure () -> String
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(condition(), "\(diagnostic()) (timed out after \(timeout) seconds)")
    }

    @MainActor
    private static func pauseFor(_ duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) {
        precondition(condition(), message())
    }
}

private enum PlaybackStateEvent: Equatable {
    case muted
    case unmuted
    case playing
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension PanelBackgroundPlaybackIntent {
    func copy(
        isEnabled: Bool? = nil,
        isVisible: Bool? = nil,
        reduceMotion: Bool? = nil,
        audioRequested: Bool? = nil,
        assetIsDynamic: Bool? = nil,
        assetHasAudio: Bool? = nil
    ) -> Self {
        Self(
            isEnabled: isEnabled ?? self.isEnabled,
            isVisible: isVisible ?? self.isVisible,
            reduceMotion: reduceMotion ?? self.reduceMotion,
            audioRequested: audioRequested ?? self.audioRequested,
            assetIsDynamic: assetIsDynamic ?? self.assetIsDynamic,
            assetHasAudio: assetHasAudio ?? self.assetHasAudio
        )
    }
}
