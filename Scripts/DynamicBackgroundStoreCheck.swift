@preconcurrency import AVFoundation
import AppKit
import Foundation
import ImageIO

@main
enum DynamicBackgroundStoreCheck {
    @MainActor
    static func main() async throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "ColdHotDynamicBackgroundStoreCheck-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: rootDirectory) }

        try checkLegacyFallback(in: rootDirectory)
        try checkSynchronousCompatibility(in: rootDirectory)
        try await checkTransactionalImports(in: rootDirectory)
        try await checkMutationIsolationAndCancellation(in: rootDirectory)
        try await checkImporterVideoCancellation(in: rootDirectory)
        try await checkSymlinkMaterializationAndTransformedPoster(in: rootDirectory)
        try await checkTypeResolutionAndUnknownExtensionLimit(in: rootDirectory)
        try await checkInjectedTransactionFailures(in: rootDirectory)
        try await checkCorruptManifestRestorationFailure(in: rootDirectory)
        try await checkSynchronousTransactionFailures(in: rootDirectory)
        try await checkStartupManifestHardening(in: rootDirectory)
        print("Dynamic background store checks passed")
    }

    @MainActor
    private static func checkSynchronousCompatibility(in rootDirectory: URL) throws {
        let directory = rootDirectory.appendingPathComponent("compatibility", isDirectory: true)
        let sourceURL = rootDirectory.appendingPathComponent("compatibility-source.png")
        try DynamicBackgroundTestMedia.makePNG(
            at: sourceURL,
            width: 2_400,
            height: 1_200
        )
        let store = PanelBackgroundStore(directoryURL: directory)
        try store.importImage(from: sourceURL)
        expect(store.asset?.kind == .staticImage, "The temporary sync API must remain static-only")
        expect(store.fileURL.lastPathComponent == "background.png", "The sync API must retain its legacy path")
        try expect(
            try pixelSize(at: store.fileURL) == CGSize(width: 1_600, height: 800),
            "The sync API must retain the existing thumbnail behavior"
        )
        expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("manifest.json").path
            ),
            "The temporary sync path must not interfere with async manifest transactions"
        )
        try store.removeImage()
        expect(!store.hasImage, "The temporary sync removal API must clear the asset")
        expect(!FileManager.default.fileExists(atPath: store.fileURL.path), "Sync removal must delete legacy PNG")
    }

    @MainActor
    private static func checkLegacyFallback(in rootDirectory: URL) throws {
        let directory = rootDirectory.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let legacyURL = directory.appendingPathComponent("background.png")
        try DynamicBackgroundTestMedia.makePNG(at: legacyURL)

        let store = PanelBackgroundStore(directoryURL: directory)
        expect(store.hasBackground, "A legacy background.png must still load")
        expect(store.hasImage, "A legacy image must remain visible through hasImage")
        expect(store.asset?.kind == .staticImage, "A legacy PNG must be a static asset")
        expect(store.asset?.mediaURL == nil, "A legacy static asset must not expose dynamic media")
        expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("manifest.json").path
            ),
            "Legacy loading must not silently publish a manifest"
        )
    }

    @MainActor
    private static func checkTransactionalImports(in rootDirectory: URL) async throws {
        let observer = PublicationObservingFileManager()
        let directory = rootDirectory.appendingPathComponent("transactional", isDirectory: true)
        observer.manifestURL = directory.appendingPathComponent("manifest.json")
        let store = PanelBackgroundStore(directoryURL: directory, fileManager: observer)

        let staticSource = rootDirectory.appendingPathComponent("static-source.png")
        try DynamicBackgroundTestMedia.makePNG(
            at: staticSource,
            width: 2_400,
            height: 1_200
        )
        observer.resetMoveObservations()
        try await store.importBackground(from: staticSource)
        let staticManifest = try loadManifest(in: directory)
        let staticManifestData = try manifestData(in: directory)
        expect(staticManifest.schemaVersion == 1, "Static import must write schema 1")
        expect(staticManifest.kind == .staticImage, "PNG import must remain static")
        expect(staticManifest.posterFilename == nil, "Static media is its own poster")
        expect(store.asset?.id == staticManifest.generationID, "Published ID must match manifest")
        expect(store.asset?.mediaURL == nil, "Static assets must not expose a player URL")
        let staticMediaURL = directory.appendingPathComponent(staticManifest.mediaFilename)
        try expect(
            try pixelSize(at: staticMediaURL) == CGSize(width: 1_600, height: 800),
            "Static import must retain the existing 1,600-pixel thumbnail behavior"
        )
        expect(
            observer.manifestSnapshotsDuringMove.allSatisfy { $0 == nil },
            "The first manifest must not exist while generation files are moving"
        )

        let gifSource = rootDirectory.appendingPathComponent("animated.gif")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifSource)
        observer.resetMoveObservations()
        try await store.importBackground(from: gifSource)
        let gifManifest = try loadManifest(in: directory)
        expect(gifManifest.kind == .convertedGIF, "GIF must publish as convertedGIF")
        expect(gifManifest.mediaFilename.hasSuffix(".mp4"), "GIF media must be MP4")
        expect(gifManifest.posterFilename?.hasSuffix(".png") == true, "GIF needs a PNG poster")
        expect(store.asset?.kind == .convertedGIF, "The in-memory asset must match the GIF manifest")
        expect(store.asset?.hasAudio == false, "Converted GIF must stay silent")
        expect(store.asset?.mediaURL?.pathExtension == "mp4", "Converted GIF needs a player URL")
        try expectManifestReferencesExistingFiles(gifManifest, in: directory)
        expect(
            observer.manifestSnapshotsDuringMove.count == 2
                && observer.manifestSnapshotsDuringMove.allSatisfy { $0 == staticManifestData },
            "The old manifest must remain published until both GIF files are in place"
        )
        expect(
            !observer.fileExists(atPath: staticMediaURL.path),
            "A committed replacement must remove the previous generation"
        )

        let silentVideo = rootDirectory.appendingPathComponent("silent.mp4")
        try await DynamicBackgroundTestMedia.makeSilentH264Video(at: silentVideo)
        let gifManifestData = try manifestData(in: directory)
        let gifURLs = urlsReferenced(by: gifManifest, in: directory)
        observer.resetMoveObservations()
        try await store.importBackground(from: silentVideo)
        let silentManifest = try loadManifest(in: directory)
        expect(silentManifest.kind == .video, "A playable MP4 must publish as video")
        expect(silentManifest.mediaFilename.hasSuffix(".mp4"), "MP4 extension must be preserved")
        expect(!silentManifest.hasAudio, "A silent video must not claim audio")
        expect(store.asset?.hasAudio == false, "Silent-video metadata must reach the asset")
        let silentStoredURL = directory.appendingPathComponent(silentManifest.mediaFilename)
        try expect(
            try Data(contentsOf: silentStoredURL) == Data(contentsOf: silentVideo),
            "Native video bytes must be copied without transcoding"
        )
        expect(
            observer.manifestSnapshotsDuringMove.count == 2
                && observer.manifestSnapshotsDuringMove.allSatisfy { $0 == gifManifestData },
            "The GIF manifest must remain published while native video files move"
        )
        expect(
            gifURLs.allSatisfy { !observer.fileExists(atPath: $0.path) },
            "Replacing a GIF must remove both of its generation files"
        )

        let audioVideo = rootDirectory.appendingPathComponent("audio.mov")
        try await DynamicBackgroundTestMedia.makeAudioVideoMOV(
            at: audioVideo,
            workingDirectory: rootDirectory.appendingPathComponent("audio-fixture", isDirectory: true)
        )
        let silentManifestData = try manifestData(in: directory)
        let silentURLs = urlsReferenced(by: silentManifest, in: directory)
        observer.resetMoveObservations()
        try await store.importBackground(from: audioVideo)
        let audioManifest = try loadManifest(in: directory)
        expect(audioManifest.kind == .video, "A playable MOV must publish as video")
        expect(audioManifest.mediaFilename.hasSuffix(".mov"), "MOV extension must be preserved")
        expect(audioManifest.hasAudio, "A real audio track must be detected")
        expect(store.asset?.hasAudio == true, "Audio metadata must reach the published asset")
        let audioStoredURL = directory.appendingPathComponent(audioManifest.mediaFilename)
        try expect(
            try Data(contentsOf: audioStoredURL) == Data(contentsOf: audioVideo),
            "MOV bytes must be copied without transcoding"
        )
        expect(
            observer.manifestSnapshotsDuringMove.count == 2
                && observer.manifestSnapshotsDuringMove.allSatisfy { $0 == silentManifestData },
            "The silent-video manifest must remain published until MOV media and poster exist"
        )
        expect(
            silentURLs.allSatisfy { !observer.fileExists(atPath: $0.path) },
            "Replacing native video must remove its prior generation"
        )

        try await checkFailedReplacementRollback(store: store, directory: directory)
        try await checkLimitsBeforeCopying(store: store, rootDirectory: rootDirectory, directory: directory)

        let stagingDirectory = directory.appendingPathComponent(
            "staging-interrupted",
            isDirectory: true
        )
        try observer.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(
            to: stagingDirectory.appendingPathComponent("partial.media")
        )
        let unrelatedURL = directory.appendingPathComponent("unrelated.keep")
        try Data("unrelated".utf8).write(to: unrelatedURL)
        let restored = PanelBackgroundStore(directoryURL: directory, fileManager: observer)
        expect(restored.asset?.id == audioManifest.generationID, "Startup must reload schema 1")
        expect(!observer.fileExists(atPath: stagingDirectory.path), "Startup must remove staging directories")
        expect(observer.fileExists(atPath: unrelatedURL.path), "Startup cleanup must remove only staging directories")

        let legacyURL = directory.appendingPathComponent("background.png")
        try DynamicBackgroundTestMedia.makePNG(at: legacyURL)
        let removalStaging = directory.appendingPathComponent("staging-remove", isDirectory: true)
        try observer.createDirectory(at: removalStaging, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: removalStaging.appendingPathComponent("partial.media"))
        let removalTargets = urlsReferenced(by: audioManifest, in: directory)
        try restored.removeBackground()
        expect(!restored.hasBackground, "Removal must clear the published asset")
        expect(
            removalTargets.allSatisfy { !observer.fileExists(atPath: $0.path) },
            "Removal must delete committed media and poster"
        )
        expect(
            !observer.fileExists(atPath: directory.appendingPathComponent("manifest.json").path),
            "Removal must delete the manifest"
        )
        expect(!observer.fileExists(atPath: legacyURL.path), "Removal must delete legacy background.png")
        expect(!observer.fileExists(atPath: removalStaging.path), "Removal must delete staging files")
        expect(observer.fileExists(atPath: unrelatedURL.path), "Removal must not delete unrelated files")
    }

    @MainActor
    private static func checkFailedReplacementRollback(
        store: PanelBackgroundStore,
        directory: URL
    ) async throws {
        let assetID = store.asset?.id
        let manifestBefore = try manifestData(in: directory)
        let filesBefore = try fileSnapshot(in: directory)
        let corruptURL = directory.deletingLastPathComponent().appendingPathComponent("corrupt.mov")
        try Data("not a movie".utf8).write(to: corruptURL)
        do {
            try await store.importBackground(from: corruptURL)
            fatalError("A corrupted replacement must throw")
        } catch {}

        expect(store.asset?.id == assetID, "Failed replacement must preserve asset identity")
        try expect(try manifestData(in: directory) == manifestBefore, "Failed replacement must preserve manifest")
        try expect(try fileSnapshot(in: directory) == filesBefore, "Failed replacement must preserve committed files")
        try expect(try stagingEntries(in: directory).isEmpty, "Failed replacement must remove staging files")
    }

    @MainActor
    private static func checkLimitsBeforeCopying(
        store: PanelBackgroundStore,
        rootDirectory: URL,
        directory: URL
    ) async throws {
        let assetID = store.asset?.id
        let manifestBefore = try manifestData(in: directory)
        let filesBefore = try fileSnapshot(in: directory)

        let oversizedGIF = rootDirectory.appendingPathComponent("oversized.gif")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: oversizedGIF)
        try DynamicBackgroundTestMedia.extendFile(
            at: oversizedGIF,
            toByteCount: PanelBackgroundImportLimits.maximumGIFBytes + 1
        )
        do {
            try await store.importBackground(from: oversizedGIF)
            fatalError("A GIF one byte above the limit must fail")
        } catch PanelBackgroundImportError.gifTooLarge {}

        let oversizedVideo = rootDirectory.appendingPathComponent("oversized.mp4")
        try Data([0]).write(to: oversizedVideo)
        try DynamicBackgroundTestMedia.extendFile(
            at: oversizedVideo,
            toByteCount: PanelBackgroundImportLimits.maximumVideoBytes + 1
        )
        do {
            try await store.importBackground(from: oversizedVideo)
            fatalError("A video one byte above the limit must fail")
        } catch PanelBackgroundImportError.videoTooLarge {}

        expect(store.asset?.id == assetID, "Over-limit imports must preserve asset identity")
        try expect(try manifestData(in: directory) == manifestBefore, "Over-limit imports must preserve manifest")
        try expect(try fileSnapshot(in: directory) == filesBefore, "Limits must be checked before copying")
        try expect(try stagingEntries(in: directory).isEmpty, "Over-limit imports must leave no staging files")
    }

    @MainActor
    private static func checkMutationIsolationAndCancellation(in rootDirectory: URL) async throws {
        let directory = rootDirectory.appendingPathComponent("mutation-isolation", isDirectory: true)
        let sourceURL = rootDirectory.appendingPathComponent("mutation-source.png")
        try DynamicBackgroundTestMedia.makePNG(at: sourceURL)
        let gate = ImportPreparationGate()
        let realImporter = PanelBackgroundMediaImporter()
        let store = PanelBackgroundStore(
            directoryURL: directory,
            prepareImport: { sourceURL, stagingDirectory in
                await gate.pause()
                try Task.checkCancellation()
                return try await realImporter.prepareImport(
                    from: sourceURL,
                    in: stagingDirectory
                )
            }
        )

        let firstImport = Task { @MainActor in
            try await store.importBackground(from: sourceURL)
        }
        await gate.waitUntilPaused()
        do {
            try await store.importBackground(from: sourceURL)
            fatalError("A second async import must be rejected while mutation is active")
        } catch PanelBackgroundImportError.operationInProgress {}
        do {
            try store.importImage(from: sourceURL)
            fatalError("The synchronous compatibility API must reject an active async import")
        } catch PanelBackgroundImportError.operationInProgress {}
        await gate.resume()
        try await firstImport.value

        let committed = try loadManifest(in: directory)
        expect(store.asset?.id == committed.generationID, "The first import must remain authoritative")
        try expectManifestReferencesExistingFiles(committed, in: directory)
        try expect(try stagingEntries(in: directory).isEmpty, "Concurrent rejection must leave no staging files")
        try expect(
            try generationEntries(in: directory).count == 1,
            "Concurrent rejection must publish exactly one static generation"
        )

        let cancellationDirectory = rootDirectory.appendingPathComponent(
            "mutation-cancellation",
            isDirectory: true
        )
        let cancellationGate = ImportPreparationGate()
        let cancellationStore = PanelBackgroundStore(
            directoryURL: cancellationDirectory,
            prepareImport: { sourceURL, stagingDirectory in
                await cancellationGate.pause()
                try Task.checkCancellation()
                return try await realImporter.prepareImport(
                    from: sourceURL,
                    in: stagingDirectory
                )
            }
        )
        let cancelledImport = Task { @MainActor in
            try await cancellationStore.importBackground(from: sourceURL)
        }
        await cancellationGate.waitUntilPaused()
        cancelledImport.cancel()
        await cancellationGate.resume()
        do {
            try await cancelledImport.value
            fatalError("Cancelled store import must throw CancellationError")
        } catch is CancellationError {}
        expect(!cancellationStore.hasBackground, "Cancellation must preserve the prior empty asset")
        expect(
            !FileManager.default.fileExists(
                atPath: cancellationDirectory.appendingPathComponent("manifest.json").path
            ),
            "Cancellation must not publish a manifest"
        )
        try expect(
            try stagingEntries(in: cancellationDirectory).isEmpty,
            "Cancellation must roll back staging files"
        )
        try cancellationStore.importImage(from: sourceURL)
        expect(cancellationStore.hasImage, "Cancellation must release the mutation guard")
    }

    @MainActor
    private static func checkImporterVideoCancellation(in rootDirectory: URL) async throws {
        let sourceURL = rootDirectory.appendingPathComponent("importer-cancellation.mp4")
        let stagingDirectory = rootDirectory.appendingPathComponent(
            "importer-cancellation-staging",
            isDirectory: true
        )
        try await DynamicBackgroundTestMedia.makeSilentH264Video(at: sourceURL)
        let gate = ImportPreparationGate()
        let importer = PanelBackgroundMediaImporter(
            loadVideoMetadata: { _ in
                await gate.pause()
                try Task.checkCancellation()
                fatalError("Cancelled metadata loading must not return metadata")
            }
        )
        let importTask = Task { @MainActor in
            try await importer.prepareImport(from: sourceURL, in: stagingDirectory)
        }
        await gate.waitUntilPaused()
        importTask.cancel()
        await gate.resume()
        do {
            _ = try await importTask.value
            fatalError("Video prepareImport cancellation must throw CancellationError")
        } catch is CancellationError {}
        expect(
            !FileManager.default.fileExists(atPath: stagingDirectory.path),
            "Cancelled prepareImport must remove its staging directory"
        )
    }

    @MainActor
    private static func checkSymlinkMaterializationAndTransformedPoster(
        in rootDirectory: URL
    ) async throws {
        let fileManager = FileManager.default
        let directory = rootDirectory.appendingPathComponent("symlink-input", isDirectory: true)
        let realVideoURL = rootDirectory.appendingPathComponent("symlink-target.mp4")
        let selectedSymlinkURL = rootDirectory.appendingPathComponent("selected-symlink.mp4")
        try await DynamicBackgroundTestMedia.makeSilentH264Video(at: realVideoURL)
        try fileManager.createSymbolicLink(at: selectedSymlinkURL, withDestinationURL: realVideoURL)

        let store = PanelBackgroundStore(directoryURL: directory)
        try await store.importBackground(from: selectedSymlinkURL)
        let symlinkManifest = try loadManifest(in: directory)
        let storedVideoURL = directory.appendingPathComponent(symlinkManifest.mediaFilename)
        let storedValues = try storedVideoURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        expect(storedValues.isRegularFile == true, "Selected video symlink must become a regular file")
        expect(storedValues.isSymbolicLink != true, "Committed video must not remain a symlink")
        try expect(
            try Data(contentsOf: storedVideoURL) == Data(contentsOf: realVideoURL),
            "Materialized symlink video bytes must match the selected target"
        )
        expect(
            isCanonicalDescendant(storedVideoURL, of: directory),
            "Committed video canonical path must remain inside PanelBackground"
        )

        let transformedDirectory = rootDirectory.appendingPathComponent(
            "preferred-transform",
            isDirectory: true
        )
        let transformedSource = rootDirectory.appendingPathComponent("preferred-transform.mov")
        try await DynamicBackgroundTestMedia.makePreferredTransformVideo(
            at: transformedSource,
            workingDirectory: rootDirectory.appendingPathComponent(
                "preferred-transform-fixture",
                isDirectory: true
            )
        )
        let sourceAsset = AVURLAsset(url: transformedSource)
        guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            fatalError("Preferred-transform fixture must contain video")
        }
        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        expect(preferredTransform != .identity, "Fixture must carry a non-identity transform")

        let transformedStore = PanelBackgroundStore(directoryURL: transformedDirectory)
        try await transformedStore.importBackground(from: transformedSource)
        let transformedManifest = try loadManifest(in: transformedDirectory)
        guard let posterFilename = transformedManifest.posterFilename else {
            fatalError("Transformed video must publish a poster")
        }
        let posterURL = transformedDirectory.appendingPathComponent(posterFilename)
        try expect(
            try pixelSize(at: posterURL) == CGSize(width: 24, height: 32),
            "Poster must apply the source track's portrait transform"
        )
        let posterColor = try centerColor(at: posterURL)
        expect(
            posterColor.redComponent > 0.7
                && posterColor.redComponent > posterColor.blueComponent * 2,
            "Exact first-frame poster must retain the red frame rather than a later blue frame"
        )
    }

    @MainActor
    private static func checkTypeResolutionAndUnknownExtensionLimit(
        in rootDirectory: URL
    ) async throws {
        let directory = rootDirectory.appendingPathComponent("type-resolution", isDirectory: true)
        let store = PanelBackgroundStore(directoryURL: directory)

        let gifNamedPNG = rootDirectory.appendingPathComponent("gif-named.png")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifNamedPNG)
        try await store.importBackground(from: gifNamedPNG)
        expect(store.asset?.kind == .staticImage, "Declared PNG type must precede ImageIO GIF content")

        let pngNamedGIF = rootDirectory.appendingPathComponent("png-named.gif")
        try DynamicBackgroundTestMedia.makePNG(at: pngNamedGIF)
        try await store.importBackground(from: pngNamedGIF)
        expect(
            store.asset?.kind == .convertedGIF,
            "Declared GIF type must precede ImageIO PNG content"
        )

        let unknownGIF = rootDirectory.appendingPathComponent("unknown-gif.payload")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: unknownGIF)
        try await store.importBackground(from: unknownGIF)
        expect(
            store.asset?.kind == .convertedGIF,
            "A bounded content probe must identify GIF when declarations are unknown"
        )

        let manifestBeforeLimit = try manifestData(in: directory)
        let filesBeforeLimit = try fileSnapshot(in: directory)
        let oversizedUnknownGIF = rootDirectory.appendingPathComponent("oversized-gif.payload")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: oversizedUnknownGIF)
        try DynamicBackgroundTestMedia.extendFile(
            at: oversizedUnknownGIF,
            toByteCount: PanelBackgroundImportLimits.maximumGIFBytes + 1
        )
        do {
            try await store.importBackground(from: oversizedUnknownGIF)
            fatalError("Unknown-extension GIF above 100 MiB must be rejected")
        } catch PanelBackgroundImportError.gifTooLarge {}
        try expect(
            try manifestData(in: directory) == manifestBeforeLimit,
            "Unknown-extension limit rejection must preserve manifest"
        )
        try expect(
            try fileSnapshot(in: directory) == filesBeforeLimit,
            "Unknown-extension limit rejection must occur before store publication"
        )
    }

    @MainActor
    private static func checkInjectedTransactionFailures(in rootDirectory: URL) async throws {
        let fileManager = TransactionFaultFileManager()
        let directory = rootDirectory.appendingPathComponent("fault-injection", isDirectory: true)
        fileManager.manifestURL = directory.appendingPathComponent("manifest.json")
        let baselineSource = rootDirectory.appendingPathComponent("fault-baseline.png")
        let gifSource = rootDirectory.appendingPathComponent("fault-replacement.gif")
        try DynamicBackgroundTestMedia.makePNG(at: baselineSource)
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifSource)
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            writeManifest: fileManager.writeManifest
        )
        try await store.importBackground(from: baselineSource)

        func capturePrior() throws -> (String?, Data, [String: Data]) {
            (store.asset?.id, try manifestData(in: directory), try fileSnapshot(in: directory))
        }
        func expectPrior(_ prior: (String?, Data, [String: Data]), _ message: String) throws {
            expect(store.asset?.id == prior.0, "\(message): asset identity changed")
            try expect(try manifestData(in: directory) == prior.1, "\(message): manifest changed")
            try expect(try fileSnapshot(in: directory) == prior.2, "\(message): files changed")
            try expect(
                try stagingEntries(in: directory).isEmpty,
                "\(message): staging files leaked"
            )
        }

        var prior = try capturePrior()
        fileManager.resetFaults()
        fileManager.failMoveDestinationPrefix = "poster-"
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Injected poster move failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectPrior(prior, "Failure after media move")

        prior = try capturePrior()
        fileManager.resetFaults()
        fileManager.failManifestOperationNumbers = [1]
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Injected manifest replacement failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectPrior(prior, "Failure after poster move")

        prior = try capturePrior()
        fileManager.resetFaults()
        fileManager.corruptManifestOperationNumbers = [1]
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Corrupt manifest replacement failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectPrior(prior, "Failure after corrupt manifest replacement")

        prior = try capturePrior()
        fileManager.resetFaults()
        fileManager.hideCommittedPosterOnce = true
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Injected committed reload failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectPrior(prior, "Failure after manifest replacement")

        fileManager.resetFaults()
        fileManager.hideCommittedPosterOnce = true
        fileManager.failManifestOperationNumbers = [2]
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Manifest restoration failure must surface")
        } catch PanelBackgroundImportError.rollbackFailed {}
        let adoptedManifest = try loadManifest(in: directory)
        expect(
            store.asset?.id == adoptedManifest.generationID,
            "Restoration failure must adopt the coherent newly committed manifest"
        )
        try expectManifestReferencesExistingFiles(adoptedManifest, in: directory)

        let adoptedURLs = urlsReferenced(by: adoptedManifest, in: directory)
        fileManager.resetFaults()
        fileManager.failRemovePaths = [adoptedURLs[0].path]
        do {
            try await store.importBackground(from: baselineSource)
            fatalError("Committed old-generation cleanup failure must surface")
        } catch PanelBackgroundImportError.cleanupFailed {}
        let cleanupManifest = try loadManifest(in: directory)
        expect(store.asset?.id == cleanupManifest.generationID, "Cleanup failure must retain new asset")
        try expectManifestReferencesExistingFiles(cleanupManifest, in: directory)
        expect(
            FileManager.default.fileExists(atPath: adoptedURLs[0].path),
            "Failed old-generation cleanup may leave only an unreferenced leftover"
        )
        fileManager.resetFaults()
        try? FileManager.default.removeItem(at: adoptedURLs[0])

        prior = try capturePrior()
        fileManager.resetFaults()
        fileManager.failMoveDestinationPrefix = "poster-"
        fileManager.failRemoveDestinationPrefix = "media-"
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Rollback cleanup failure must surface")
        } catch PanelBackgroundImportError.rollbackFailed {}
        expect(store.asset?.id == prior.0, "Rollback cleanup failure must preserve prior asset")
        try expect(try manifestData(in: directory) == prior.1, "Rollback cleanup must preserve manifest")
        let currentManifest = try loadManifest(in: directory)
        try expectManifestReferencesExistingFiles(currentManifest, in: directory)
        try expect(
            try fileSnapshot(in: directory).count == prior.2.count + 1,
            "Rollback cleanup failure may leave one surfaced unreferenced media file"
        )
    }

    @MainActor
    private static func checkCorruptManifestRestorationFailure(
        in rootDirectory: URL
    ) async throws {
        let fileManager = TransactionFaultFileManager()
        let directory = rootDirectory.appendingPathComponent(
            "corrupt-restoration-failure",
            isDirectory: true
        )
        fileManager.manifestURL = directory.appendingPathComponent("manifest.json")
        let baselineSource = rootDirectory.appendingPathComponent(
            "corrupt-restoration-baseline.png"
        )
        let gifSource = rootDirectory.appendingPathComponent("corrupt-restoration.gif")
        try DynamicBackgroundTestMedia.makePNG(at: baselineSource)
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifSource)
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            writeManifest: fileManager.writeManifest
        )
        try await store.importBackground(from: baselineSource)

        let protectedManifest = try loadManifest(in: directory)
        let protectedURLs = urlsReferenced(by: protectedManifest, in: directory)
        let protectedData = try Dictionary(
            uniqueKeysWithValues: protectedURLs.map {
                ($0.lastPathComponent, try Data(contentsOf: $0))
            }
        )
        fileManager.resetFaults()
        fileManager.corruptManifestOperationNumbers = [1]
        fileManager.failManifestOperationNumbers = [2]
        do {
            try await store.importBackground(from: gifSource)
            fatalError("Corrupt replacement plus restoration failure must throw")
        } catch PanelBackgroundImportError.rollbackFailed {}
        expect(store.asset == nil, "Invalid surviving manifest must not retain a stale prior asset")
        expect(
            !fileManager.fileExists(atPath: directory.appendingPathComponent("manifest.json").path),
            "Invalid surviving manifest must be removed or quarantined"
        )
        for protectedURL in protectedURLs {
            try expect(
                try Data(contentsOf: protectedURL) == protectedData[protectedURL.lastPathComponent],
                "Failed restoration must protect the prior generation bytes"
            )
        }
        try expect(
            Set(try generationEntries(in: directory).map(\.lastPathComponent))
                == Set(protectedURLs.map(\.lastPathComponent)),
            "Invalid-manifest recovery must remove only the candidate generation"
        )
        try expect(
            try stagingEntries(in: directory).isEmpty,
            "Invalid-manifest recovery must remove staging files"
        )
        fileManager.resetFaults()
        expect(
            PanelBackgroundStore(directoryURL: directory, fileManager: fileManager).asset == nil,
            "Invalid-manifest recovery must remain coherent after restart"
        )
    }

    @MainActor
    private static func checkSynchronousTransactionFailures(in rootDirectory: URL) async throws {
        let fileManager = TransactionFaultFileManager()
        let directory = rootDirectory.appendingPathComponent("sync-faults", isDirectory: true)
        fileManager.manifestURL = directory.appendingPathComponent("manifest.json")
        let gifSource = rootDirectory.appendingPathComponent("sync-baseline.gif")
        let staticSource = rootDirectory.appendingPathComponent("sync-replacement.png")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifSource)
        try DynamicBackgroundTestMedia.makePNG(at: staticSource)
        let store = PanelBackgroundStore(
            directoryURL: directory,
            fileManager: fileManager,
            writeManifest: fileManager.writeManifest,
            writeLegacy: fileManager.writeLegacy
        )
        try await store.importBackground(from: gifSource)

        let priorID = store.asset?.id
        let priorManifest = try manifestData(in: directory)
        let priorFiles = try fileSnapshot(in: directory)

        func expectExactPrior(_ message: String) throws {
            expect(store.asset?.id == priorID, "\(message): asset identity changed")
            try expect(try manifestData(in: directory) == priorManifest, "\(message): manifest changed")
            try expect(try fileSnapshot(in: directory) == priorFiles, "\(message): files changed")
            try expect(try stagingEntries(in: directory).isEmpty, "\(message): staging leaked")
            fileManager.resetFaults()
            expect(
                PanelBackgroundStore(directoryURL: directory, fileManager: fileManager).asset?.id
                    == priorID,
                "\(message): restarted asset changed"
            )
        }

        fileManager.resetFaults()
        fileManager.failLegacyWriteAfterReplacement = true
        do {
            try store.importImage(from: staticSource)
            fatalError("Post-replacement legacy write failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectExactPrior("Post-replacement legacy write failure")

        fileManager.resetFaults()
        fileManager.failRemoveAfterSideEffectPaths = [
            directory.appendingPathComponent("manifest.json").path
        ]
        do {
            try store.importImage(from: staticSource)
            fatalError("Post-removal manifest failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        try expectExactPrior("Post-removal manifest failure")

        fileManager.resetFaults()
        fileManager.failRemovePaths = [directory.appendingPathComponent("manifest.json").path]
        do {
            try store.importImage(from: staticSource)
            fatalError("Compatibility manifest-removal failure must throw")
        } catch PanelBackgroundImportError.unableToWrite {}
        expect(store.asset?.id == priorID, "Sync publication failure must preserve prior asset")
        try expect(try manifestData(in: directory) == priorManifest, "Sync failure must preserve manifest")
        try expect(try fileSnapshot(in: directory) == priorFiles, "Sync failure must restore legacy output")

        let oldManifest = try loadManifest(in: directory)
        let oldURLs = urlsReferenced(by: oldManifest, in: directory)
        fileManager.resetFaults()
        fileManager.failRemovePaths = [oldURLs[0].path]
        do {
            try store.importImage(from: staticSource)
            fatalError("Compatibility old-generation cleanup failure must surface")
        } catch PanelBackgroundImportError.cleanupFailed {}
        expect(store.asset?.kind == .staticImage, "Sync cleanup failure must keep new legacy asset")
        expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("manifest.json").path
            ),
            "Sync cleanup failure must leave legacy publication authoritative"
        )
        let legacyValues = try store.fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        expect(legacyValues.isRegularFile == true, "Sync committed legacy output must be regular")
        expect(legacyValues.isSymbolicLink != true, "Sync committed legacy output must not be a symlink")
        expect(FileManager.default.fileExists(atPath: oldURLs[0].path), "Failed cleanup may leave old media")
    }

    @MainActor
    private static func checkStartupManifestHardening(in rootDirectory: URL) async throws {
        let outsidePNG = rootDirectory.appendingPathComponent("manifest-outside.png")
        try DynamicBackgroundTestMedia.makePNG(at: outsidePNG)

        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "unsupported-schema",
            manifest: PanelBackgroundManifest(
                schemaVersion: 2,
                generationID: "unsupported",
                kind: .staticImage,
                mediaFilename: "media.png",
                posterFilename: nil,
                originalTypeIdentifier: "public.png",
                hasAudio: false
            ),
            setup: { directory in
                try DynamicBackgroundTestMedia.makePNG(
                    at: directory.appendingPathComponent("media.png")
                )
            }
        )
        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "traversal-media",
            manifest: PanelBackgroundManifest(
                schemaVersion: 1,
                generationID: "traversal",
                kind: .staticImage,
                mediaFilename: "../manifest-outside.png",
                posterFilename: nil,
                originalTypeIdentifier: "public.png",
                hasAudio: false
            )
        )
        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "absolute-media",
            manifest: PanelBackgroundManifest(
                schemaVersion: 1,
                generationID: "absolute",
                kind: .staticImage,
                mediaFilename: outsidePNG.path,
                posterFilename: nil,
                originalTypeIdentifier: "public.png",
                hasAudio: false
            )
        )
        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "unsafe-static-poster",
            manifest: PanelBackgroundManifest(
                schemaVersion: 1,
                generationID: "unsafe-poster",
                kind: .staticImage,
                mediaFilename: "media.png",
                posterFilename: "poster\\escape.png",
                originalTypeIdentifier: "public.png",
                hasAudio: false
            ),
            setup: { directory in
                try DynamicBackgroundTestMedia.makePNG(
                    at: directory.appendingPathComponent("media.png")
                )
                try DynamicBackgroundTestMedia.makePNG(
                    at: directory.appendingPathComponent("poster\\escape.png")
                )
            }
        )
        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "symlink-media",
            manifest: PanelBackgroundManifest(
                schemaVersion: 1,
                generationID: "symlink-media",
                kind: .staticImage,
                mediaFilename: "media.png",
                posterFilename: nil,
                originalTypeIdentifier: "public.png",
                hasAudio: false
            ),
            setup: { directory in
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent("media.png"),
                    withDestinationURL: outsidePNG
                )
            }
        )
        try checkRejectedStartupManifest(
            in: rootDirectory,
            name: "symlink-poster",
            manifest: PanelBackgroundManifest(
                schemaVersion: 1,
                generationID: "symlink-poster",
                kind: .video,
                mediaFilename: "media.mov",
                posterFilename: "poster.png",
                originalTypeIdentifier: "com.apple.quicktime-movie",
                hasAudio: false
            ),
            setup: { directory in
                try Data("regular media".utf8).write(
                    to: directory.appendingPathComponent("media.mov")
                )
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent("poster.png"),
                    withDestinationURL: outsidePNG
                )
            }
        )

        let malformedDirectory = rootDirectory.appendingPathComponent(
            "startup-malformed",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: malformedDirectory,
            withIntermediateDirectories: true
        )
        try DynamicBackgroundTestMedia.makePNG(
            at: malformedDirectory.appendingPathComponent("background.png")
        )
        try Data("{ malformed".utf8).write(
            to: malformedDirectory.appendingPathComponent("manifest.json")
        )
        expect(
            PanelBackgroundStore(directoryURL: malformedDirectory).asset?.id
                == "legacy-background.png",
            "Malformed manifest must fall back to legacy PNG"
        )

        let survivingDirectory = rootDirectory.appendingPathComponent(
            "startup-current-survives",
            isDirectory: true
        )
        let sourceURL = rootDirectory.appendingPathComponent("startup-current.png")
        try DynamicBackgroundTestMedia.makePNG(at: sourceURL)
        let store = PanelBackgroundStore(directoryURL: survivingDirectory)
        try await store.importBackground(from: sourceURL)
        let manifest = try loadManifest(in: survivingDirectory)
        let referencedURL = survivingDirectory.appendingPathComponent(manifest.mediaFilename)
        let referencedData = try Data(contentsOf: referencedURL)
        let stagingDirectory = survivingDirectory.appendingPathComponent(
            "staging-interrupted",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: stagingDirectory.appendingPathComponent(manifest.mediaFilename),
            withDestinationURL: referencedURL
        )
        let restored = PanelBackgroundStore(directoryURL: survivingDirectory)
        expect(restored.asset?.id == manifest.generationID, "Current manifest must survive staging cleanup")
        try expect(
            try Data(contentsOf: referencedURL) == referencedData,
            "Staging cleanup must not follow symlinks into current generation"
        )
        expect(!FileManager.default.fileExists(atPath: stagingDirectory.path), "Staging directory must be removed")
    }

    @MainActor
    private static func checkRejectedStartupManifest(
        in rootDirectory: URL,
        name: String,
        manifest: PanelBackgroundManifest,
        setup: (URL) throws -> Void = { _ in }
    ) throws {
        let directory = rootDirectory.appendingPathComponent("startup-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DynamicBackgroundTestMedia.makePNG(
            at: directory.appendingPathComponent("background.png")
        )
        try setup(directory)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        let store = PanelBackgroundStore(directoryURL: directory)
        expect(
            store.asset?.id == "legacy-background.png",
            "Unsafe startup manifest \(name) must fall back to legacy PNG"
        )
    }

    private static func generationEntries(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("media-")
                || $0.lastPathComponent.hasPrefix("poster-")
        }
    }

    private static func centerColor(at url: URL) throws -> NSColor {
        guard let representation = NSBitmapImageRep(data: try Data(contentsOf: url)),
              let color = representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh / 2
              )?.usingColorSpace(NSColorSpace.sRGB) else {
            throw StoreCheckError.unreadableImage
        }
        return color
    }

    private static func isCanonicalDescendant(_ child: URL, of directory: URL) -> Bool {
        let rootPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let childPath = child.resolvingSymlinksInPath().standardizedFileURL.path
        return childPath.hasPrefix(rootPath + "/")
    }

    private static func loadManifest(in directory: URL) throws -> PanelBackgroundManifest {
        try JSONDecoder().decode(
            PanelBackgroundManifest.self,
            from: manifestData(in: directory)
        )
    }

    private static func manifestData(in directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    }

    private static func urlsReferenced(
        by manifest: PanelBackgroundManifest,
        in directory: URL
    ) -> [URL] {
        [manifest.mediaFilename, manifest.posterFilename]
            .compactMap { $0 }
            .map(directory.appendingPathComponent)
    }

    private static func expectManifestReferencesExistingFiles(
        _ manifest: PanelBackgroundManifest,
        in directory: URL
    ) throws {
        let fileManager = FileManager.default
        expect(
            urlsReferenced(by: manifest, in: directory).allSatisfy {
                fileManager.fileExists(atPath: $0.path)
            },
            "Every published manifest filename must already exist"
        )
    }

    private static func pixelSize(at url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw StoreCheckError.unreadableImage
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func fileSnapshot(in directory: URL) throws -> [String: Data] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).reduce(into: [:]) { snapshot, url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory != true {
                snapshot[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
    }

    private static func stagingEntries(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("staging-") }
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) rethrows {
        guard try condition() else { fatalError(message) }
    }
}

private final class PublicationObservingFileManager: FileManager, @unchecked Sendable {
    var manifestURL: URL?
    private(set) var manifestSnapshotsDuringMove: [Data?] = []

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        manifestSnapshotsDuringMove.append(manifestURL.flatMap { try? Data(contentsOf: $0) })
        try super.moveItem(at: srcURL, to: dstURL)
    }

    func resetMoveObservations() {
        manifestSnapshotsDuringMove = []
    }
}

private actor ImportPreparationGate {
    private var isPaused = false
    private var isReleased = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        isPaused = true
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func resume() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class TransactionFaultFileManager: FileManager, @unchecked Sendable {
    var manifestURL: URL?
    var failMoveDestinationPrefix: String?
    var failRemoveDestinationPrefix: String?
    var failRemovePaths: Set<String> = []
    var failRemoveAfterSideEffectPaths: Set<String> = []
    var failManifestOperationNumbers: Set<Int> = []
    var corruptManifestOperationNumbers: Set<Int> = []
    var failLegacyWriteAfterReplacement = false
    var hideCommittedPosterOnce = false

    private var manifestOperationCount = 0
    private var failedRemovePaths: Set<String> = []
    private var didFailRemovePrefix = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let prefix = failMoveDestinationPrefix,
           dstURL.lastPathComponent.hasPrefix(prefix) {
            throw StoreInjectedFailure.requested
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    func writeManifest(_ data: Data, to url: URL) throws {
        try beginManifestOperation()
        if corruptManifestOperationNumbers.contains(manifestOperationCount) {
            try Data("{ corrupt".utf8).write(to: url, options: .atomic)
            throw StoreInjectedFailure.requested
        }
        try data.write(to: url, options: .atomic)
    }

    func writeLegacy(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        if failLegacyWriteAfterReplacement {
            failLegacyWriteAfterReplacement = false
            throw StoreInjectedFailure.requested
        }
    }

    override func removeItem(at URL: URL) throws {
        if failRemoveAfterSideEffectPaths.contains(URL.path) {
            failRemoveAfterSideEffectPaths.remove(URL.path)
            try super.removeItem(at: URL)
            throw StoreInjectedFailure.requested
        }
        if failRemovePaths.contains(URL.path), !failedRemovePaths.contains(URL.path) {
            failedRemovePaths.insert(URL.path)
            throw StoreInjectedFailure.requested
        }
        if let prefix = failRemoveDestinationPrefix,
           URL.lastPathComponent.hasPrefix(prefix),
           !didFailRemovePrefix {
            didFailRemovePrefix = true
            throw StoreInjectedFailure.requested
        }
        try super.removeItem(at: URL)
    }

    override func fileExists(atPath path: String) -> Bool {
        if hideCommittedPosterOnce,
           manifestOperationCount > 0,
           URL(fileURLWithPath: path).lastPathComponent.hasPrefix("poster-") {
            hideCommittedPosterOnce = false
            return false
        }
        return super.fileExists(atPath: path)
    }

    func resetFaults() {
        failMoveDestinationPrefix = nil
        failRemoveDestinationPrefix = nil
        failRemovePaths = []
        failRemoveAfterSideEffectPaths = []
        failManifestOperationNumbers = []
        corruptManifestOperationNumbers = []
        failLegacyWriteAfterReplacement = false
        hideCommittedPosterOnce = false
        manifestOperationCount = 0
        failedRemovePaths = []
        didFailRemovePrefix = false
    }

    private func beginManifestOperation() throws {
        manifestOperationCount += 1
        if failManifestOperationNumbers.contains(manifestOperationCount) {
            throw StoreInjectedFailure.requested
        }
    }
}

private enum StoreInjectedFailure: Error {
    case requested
}

private enum StoreCheckError: Error {
    case unreadableImage
}
