import AppKit
import Combine
import Foundation
import ImageIO

typealias PanelBackgroundPrepareImport = (
    _ sourceURL: URL,
    _ stagingDirectory: URL
) async throws -> PanelBackgroundPreparedImport

typealias PanelBackgroundWriteManifest = (_ data: Data, _ manifestURL: URL) throws -> Void

@MainActor
final class PanelBackgroundStore: ObservableObject {
    static let maximumPixelDimension = 1_600

    @Published private(set) var asset: PanelBackgroundAsset?

    let fileURL: URL

    var image: NSImage? { asset?.posterImage }
    var hasImage: Bool { asset != nil }
    var hasBackground: Bool { asset != nil }

    private let directoryURL: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let prepareImport: PanelBackgroundPrepareImport
    private let writeManifestOperation: PanelBackgroundWriteManifest
    private var mutationInProgress = false

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        prepareImport: PanelBackgroundPrepareImport? = nil,
        writeManifest: PanelBackgroundWriteManifest? = nil
    ) {
        self.fileManager = fileManager
        let resolvedDirectory = directoryURL
            ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.directoryURL = resolvedDirectory
        fileURL = resolvedDirectory.appendingPathComponent("background.png")
        manifestURL = resolvedDirectory.appendingPathComponent("manifest.json")

        let importer = PanelBackgroundMediaImporter(fileManager: fileManager)
        self.prepareImport = prepareImport ?? { sourceURL, stagingDirectory in
            try await importer.prepareImport(from: sourceURL, in: stagingDirectory)
        }
        writeManifestOperation = writeManifest ?? { data, url in
            try data.write(to: url, options: .atomic)
        }

        Self.cleanStagingDirectories(in: resolvedDirectory, fileManager: fileManager)
        asset = Self.loadManifestAsset(
            from: manifestURL,
            directoryURL: resolvedDirectory,
            fileManager: fileManager
        ) ?? Self.loadLegacyAsset(
            at: fileURL,
            directoryURL: resolvedDirectory,
            fileManager: fileManager
        )
    }

    func importBackground(from sourceURL: URL) async throws {
        try beginMutation()
        defer { mutationInProgress = false }

        let isAccessingSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try createStoreDirectory()
        let generationID = UUID().uuidString
        let stagingDirectory = directoryURL.appendingPathComponent(
            "staging-\(generationID)",
            isDirectory: true
        )
        let previousManifestData = try? Data(contentsOf: manifestURL)
        let previousManifest = previousManifestData.flatMap(Self.decodeManifest)
        var finalURLs: [URL] = []
        var published = false

        do {
            let prepared = try await prepareImport(sourceURL, stagingDirectory)
            try Task.checkCancellation()

            let mediaFilename = Self.generationFilename(
                prefix: "media",
                generationID: generationID,
                pathExtension: prepared.mediaURL.pathExtension
            )
            let mediaURL = directoryURL.appendingPathComponent(mediaFilename)
            do {
                try fileManager.moveItem(at: prepared.mediaURL, to: mediaURL)
                finalURLs.append(mediaURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PanelBackgroundImportError.unableToWrite
            }

            var posterFilename: String?
            if let preparedPosterURL = prepared.posterURL {
                let filename = Self.generationFilename(
                    prefix: "poster",
                    generationID: generationID,
                    pathExtension: "png"
                )
                let posterURL = directoryURL.appendingPathComponent(filename)
                do {
                    try fileManager.moveItem(at: preparedPosterURL, to: posterURL)
                    finalURLs.append(posterURL)
                    posterFilename = filename
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw PanelBackgroundImportError.unableToWrite
                }
            }

            let manifest = PanelBackgroundManifest(
                schemaVersion: PanelBackgroundManifest.currentSchemaVersion,
                generationID: generationID,
                kind: prepared.kind,
                mediaFilename: mediaFilename,
                posterFilename: posterFilename,
                originalTypeIdentifier: prepared.originalTypeIdentifier,
                hasAudio: prepared.hasAudio
            )
            guard Self.loadAsset(
                from: manifest,
                directoryURL: directoryURL,
                fileManager: fileManager
            ) != nil else {
                throw PanelBackgroundImportError.unableToWrite
            }

            let data = try Self.encodeManifest(manifest)
            do {
                try writeManifestOperation(data, manifestURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PanelBackgroundImportError.unableToWrite
            }

            guard let committedAsset = Self.loadManifestAsset(
                from: manifestURL,
                directoryURL: directoryURL,
                fileManager: fileManager
            ), committedAsset.id == generationID else {
                throw PanelBackgroundImportError.unableToWrite
            }

            asset = committedAsset
            published = true
            var cleanupFailed = false
            cleanupFailed = removeFilesReferenced(
                by: previousManifest,
                excluding: manifest
            ) || cleanupFailed
            cleanupFailed = removeIfPresent(fileURL) || cleanupFailed
            cleanupFailed = removeIfPresent(stagingDirectory) || cleanupFailed
            if cleanupFailed {
                throw PanelBackgroundImportError.cleanupFailed
            }
        } catch {
            if published {
                let stageCleanupFailed = removeIfPresent(stagingDirectory)
                let errorIsCleanupFailure: Bool
                if case PanelBackgroundImportError.cleanupFailed = error {
                    errorIsCleanupFailure = true
                } else {
                    errorIsCleanupFailure = false
                }
                if stageCleanupFailed, !errorIsCleanupFailure {
                    throw PanelBackgroundImportError.cleanupFailed
                }
                throw error
            }
            try recoverFailedImport(
                originalError: error,
                previousManifestData: previousManifestData,
                finalURLs: finalURLs,
                stagingDirectory: stagingDirectory
            )
        }
    }

    func removeBackground() throws {
        try beginMutation()
        defer { mutationInProgress = false }

        let manifest = Self.loadManifest(from: manifestURL, fileManager: fileManager)
        if manifest != nil {
            if removeIfPresent(fileURL) {
                throw PanelBackgroundImportError.unableToWrite
            }
            do {
                try fileManager.removeItem(at: manifestURL)
            } catch {
                throw PanelBackgroundImportError.unableToWrite
            }
            asset = nil
            var cleanupFailed = removeFilesReferenced(by: manifest, excluding: nil)
            cleanupFailed = removeStagingDirectories() || cleanupFailed
            if cleanupFailed {
                throw PanelBackgroundImportError.cleanupFailed
            }
            return
        }

        if removeIfPresent(fileURL) {
            throw PanelBackgroundImportError.unableToWrite
        }
        asset = nil
        if removeStagingDirectories() {
            throw PanelBackgroundImportError.cleanupFailed
        }
    }

    private func beginMutation() throws {
        guard !mutationInProgress else {
            throw PanelBackgroundImportError.operationInProgress
        }
        mutationInProgress = true
    }

    private func createStoreDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }
    }

    private func recoverFailedImport(
        originalError: Error,
        previousManifestData: Data?,
        finalURLs: [URL],
        stagingDirectory: URL
    ) throws -> Never {
        let manifestExists = fileManager.fileExists(atPath: manifestURL.path)
        let diskManifestData = try? Data(contentsOf: manifestURL)
        let manifestMayHaveChanged = diskManifestData != previousManifestData
            || (manifestExists && diskManifestData == nil)

        if manifestMayHaveChanged {
            do {
                try restoreManifest(previousManifestData)
            } catch {
                if let coherentAsset = Self.loadManifestAsset(
                    from: manifestURL,
                    directoryURL: directoryURL,
                    fileManager: fileManager
                ) {
                    asset = coherentAsset
                    _ = removeUnreferenced(finalURLs)
                } else {
                    _ = clearInvalidManifest()
                    asset = loadAuthoritativeAssetFromDisk()
                    _ = removeKnownUnreferenced(finalURLs)
                }
                _ = removeIfPresent(stagingDirectory)
                throw PanelBackgroundImportError.rollbackFailed
            }
        }

        asset = Self.loadManifestAsset(
            from: manifestURL,
            directoryURL: directoryURL,
            fileManager: fileManager
        ) ?? Self.loadLegacyAsset(
            at: fileURL,
            directoryURL: directoryURL,
            fileManager: fileManager
        )

        let cleanupFailed = removeUnreferenced(finalURLs)
            || removeIfPresent(stagingDirectory)
        if cleanupFailed {
            throw PanelBackgroundImportError.rollbackFailed
        }

        throw originalError
    }

    private func clearInvalidManifest() -> Bool {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return false }
        do {
            try fileManager.removeItem(at: manifestURL)
            return false
        } catch {
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return false
            }
            let quarantineURL = directoryURL.appendingPathComponent(
                "invalid-manifest-\(UUID().uuidString).json"
            )
            do {
                try fileManager.moveItem(at: manifestURL, to: quarantineURL)
                return false
            } catch {
                return true
            }
        }
    }

    private func restoreManifest(_ previousData: Data?) throws {
        if let previousData {
            try writeManifestOperation(previousData, manifestURL)
        } else if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
    }

    private func loadAuthoritativeAssetFromDisk() -> PanelBackgroundAsset? {
        Self.loadManifestAsset(
            from: manifestURL,
            directoryURL: directoryURL,
            fileManager: fileManager
        ) ?? Self.loadLegacyAsset(
            at: fileURL,
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    private func removeUnreferenced(_ urls: [URL]) -> Bool {
        let currentManifestData = try? Data(contentsOf: manifestURL)
        let currentManifest = currentManifestData.flatMap(Self.decodeManifest)
        if currentManifestData != nil, currentManifest == nil {
            return true
        }
        let retainedPaths = Set(
            Self.referenceURLsForCleanup(
                currentManifest,
                directoryURL: directoryURL,
                fileManager: fileManager
            ).map(\.path)
        )
        var failed = false
        for url in Set(urls.map(\.path)).map({ URL(fileURLWithPath: $0) })
        where !retainedPaths.contains(url.path) {
            failed = removeIfPresent(url) || failed
        }
        return failed
    }

    private func removeKnownUnreferenced(_ urls: [URL]) -> Bool {
        var failed = false
        for url in Set(urls.map(\.path)).map({ URL(fileURLWithPath: $0) }) {
            failed = removeIfPresent(url) || failed
        }
        return failed
    }

    private func removeFilesReferenced(
        by oldManifest: PanelBackgroundManifest?,
        excluding newManifest: PanelBackgroundManifest?
    ) -> Bool {
        let retainedPaths = Set(
            Self.referenceURLsForCleanup(
                newManifest,
                directoryURL: directoryURL,
                fileManager: fileManager
            ).map(\.path)
        )
        var failed = false
        for url in Self.referenceURLsForCleanup(
            oldManifest,
            directoryURL: directoryURL,
            fileManager: fileManager
        ) where !retainedPaths.contains(url.path) {
            failed = removeIfPresent(url) || failed
        }
        return failed
    }

    private func removeIfPresent(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        do {
            try fileManager.removeItem(at: url)
            return false
        } catch {
            return true
        }
    }

    private func removeStagingDirectories() -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        var failed = false
        for url in contents where url.lastPathComponent.hasPrefix("staging-") {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                failed = removeIfPresent(url) || failed
            }
        }
        return failed
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("ColdHot", isDirectory: true)
            .appendingPathComponent("PanelBackground", isDirectory: true)
    }

    private static func generationFilename(
        prefix: String,
        generationID: String,
        pathExtension: String
    ) -> String {
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        return "\(prefix)-\(generationID)\(suffix)"
    }

    private static func encodeManifest(_ manifest: PanelBackgroundManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }

    private static func decodeManifest(_ data: Data) -> PanelBackgroundManifest? {
        try? JSONDecoder().decode(PanelBackgroundManifest.self, from: data)
    }

    private static func loadManifestAsset(
        from manifestURL: URL,
        directoryURL: URL,
        fileManager: FileManager
    ) -> PanelBackgroundAsset? {
        guard let manifest = loadManifest(from: manifestURL, fileManager: fileManager) else {
            return nil
        }
        return loadAsset(
            from: manifest,
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    private static func loadAsset(
        from manifest: PanelBackgroundManifest,
        directoryURL: URL,
        fileManager: FileManager
    ) -> PanelBackgroundAsset? {
        guard manifest.schemaVersion == PanelBackgroundManifest.currentSchemaVersion,
              isSafeFilename(manifest.mediaFilename),
              manifest.posterFilename.map(isSafeFilename) ?? true else {
            return nil
        }

        let mediaURL = directoryURL.appendingPathComponent(manifest.mediaFilename)
        guard isActualRegularFile(
            mediaURL,
            inside: directoryURL,
            fileManager: fileManager
        ) else {
            return nil
        }
        let posterURL = manifest.posterFilename.map(directoryURL.appendingPathComponent)
        if let posterURL,
           !isActualRegularFile(
                posterURL,
                inside: directoryURL,
                fileManager: fileManager
           ) {
            return nil
        }

        let imageURL: URL
        switch manifest.kind {
        case .staticImage:
            imageURL = mediaURL
        case .convertedGIF, .video:
            guard let posterURL else { return nil }
            imageURL = posterURL
        }
        guard let posterImage = loadImage(at: imageURL) else { return nil }
        return PanelBackgroundAsset(
            id: manifest.generationID,
            kind: manifest.kind,
            posterImage: posterImage,
            mediaURL: manifest.kind.isDynamic ? mediaURL : nil,
            hasAudio: manifest.hasAudio
        )
    }

    private static func loadManifest(
        from url: URL,
        fileManager: FileManager
    ) -> PanelBackgroundManifest? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decodeManifest(data)
    }

    private static func referenceURLsForCleanup(
        _ manifest: PanelBackgroundManifest?,
        directoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        guard let manifest else { return [] }
        return [manifest.mediaFilename, manifest.posterFilename]
            .compactMap { $0 }
            .filter(isSafeFilename)
            .map { directoryURL.appendingPathComponent($0) }
            .filter {
                isCanonicalDescendant($0, of: directoryURL)
                    && ((try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink
                        != true)
            }
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty,
              !(filename as NSString).isAbsolutePath,
              filename != ".",
              filename != "..",
              !filename.contains("/"),
              !filename.contains("\\") else {
            return false
        }
        return filename == URL(fileURLWithPath: filename).lastPathComponent
    }

    private static func isActualRegularFile(
        _ url: URL,
        inside directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              isCanonicalDescendant(url, of: directoryURL),
              let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return false
        }
        return true
    }

    private static func isCanonicalDescendant(_ url: URL, of directoryURL: URL) -> Bool {
        let rootPath = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }

    private static func loadLegacyAsset(
        at url: URL,
        directoryURL: URL,
        fileManager: FileManager
    ) -> PanelBackgroundAsset? {
        guard isActualRegularFile(
            url,
            inside: directoryURL,
            fileManager: fileManager
        ), let image = loadImage(at: url) else {
            return nil
        }
        return PanelBackgroundAsset(
            id: legacyAssetID,
            kind: .staticImage,
            posterImage: image,
            mediaURL: nil,
            hasAudio: false
        )
    }

    private static func loadImage(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func cleanStagingDirectories(
        in directoryURL: URL,
        fileManager: FileManager
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix("staging-") {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static let legacyAssetID = "legacy-background.png"
}
