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

private enum StoreCheckError: Error {
    case unreadableImage
}
