import AppKit
import Combine
import Foundation
import ImageIO

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
    private let importer: PanelBackgroundMediaImporter

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let resolvedDirectory = directoryURL
            ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.directoryURL = resolvedDirectory
        fileURL = resolvedDirectory.appendingPathComponent("background.png")
        manifestURL = resolvedDirectory.appendingPathComponent("manifest.json")
        importer = PanelBackgroundMediaImporter(fileManager: fileManager)

        Self.cleanStagingDirectories(in: resolvedDirectory, fileManager: fileManager)
        asset = Self.loadManifestAsset(
            from: manifestURL,
            directoryURL: resolvedDirectory,
            fileManager: fileManager
        ) ?? Self.loadLegacyAsset(at: fileURL)
    }

    func importBackground(from sourceURL: URL) async throws {
        let isAccessingSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }

        let generationID = UUID().uuidString
        let stagingDirectory = directoryURL.appendingPathComponent(
            "staging-\(generationID)",
            isDirectory: true
        )
        let previousManifestData = try? Data(contentsOf: manifestURL)
        let previousManifest = previousManifestData.flatMap {
            try? JSONDecoder().decode(PanelBackgroundManifest.self, from: $0)
        }
        var publishedURLs: [URL] = []
        var manifestWasWritten = false
        var committed = false

        defer {
            try? fileManager.removeItem(at: stagingDirectory)
            if !committed {
                for url in publishedURLs {
                    try? fileManager.removeItem(at: url)
                }
                if manifestWasWritten {
                    restoreManifest(previousManifestData)
                }
            }
        }

        let prepared = try await importer.prepareImport(
            from: sourceURL,
            in: stagingDirectory
        )
        try Task.checkCancellation()

        let mediaFilename = Self.generationFilename(
            prefix: "media",
            generationID: generationID,
            pathExtension: prepared.mediaURL.pathExtension
        )
        let mediaURL = directoryURL.appendingPathComponent(mediaFilename)
        do {
            try fileManager.moveItem(at: prepared.mediaURL, to: mediaURL)
            publishedURLs.append(mediaURL)
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
                publishedURLs.append(posterURL)
                posterFilename = filename
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
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(manifest)
            manifestWasWritten = true
            try data.write(to: manifestURL, options: .atomic)
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
        committed = true
        removeFilesReferenced(by: previousManifest, excluding: manifest)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func removeBackground() throws {
        let manifest = Self.loadManifest(
            from: manifestURL,
            fileManager: fileManager
        )
        var firstError: Error?

        for url in Self.urlsReferenced(
            by: manifest,
            directoryURL: directoryURL
        ) + [manifestURL, fileURL] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                firstError = firstError ?? error
            }
        }
        Self.cleanStagingDirectories(in: directoryURL, fileManager: fileManager)

        if let firstError {
            throw firstError
        }
        asset = nil
    }

    // Temporary synchronous compatibility for Settings until its async picker migration.
    func importImage(from sourceURL: URL) throws {
        let isAccessingSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }
        let stagingDirectory = directoryURL.appendingPathComponent(
            "staging-compatibility-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }

        let preparedURL = stagingDirectory.appendingPathComponent("background.png")
        try PanelBackgroundMediaImporter.writeStaticThumbnail(
            from: sourceURL,
            to: preparedURL
        )
        guard let preparedImage = Self.loadImage(at: preparedURL) else {
            throw PanelBackgroundImportError.unreadableMedia
        }
        do {
            let data = try Data(contentsOf: preparedURL)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }

        let previousManifest = Self.loadManifest(
            from: manifestURL,
            fileManager: fileManager
        )
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        removeFilesReferenced(by: previousManifest, excluding: nil)
        asset = PanelBackgroundAsset(
            id: Self.legacyAssetID,
            kind: .staticImage,
            posterImage: preparedImage,
            mediaURL: nil,
            hasAudio: false
        )
    }

    // Temporary synchronous compatibility for Settings until Task 6.
    func removeImage() throws {
        try removeBackground()
    }

    private func restoreManifest(_ previousData: Data?) {
        if let previousData {
            try? previousData.write(to: manifestURL, options: .atomic)
        } else if fileManager.fileExists(atPath: manifestURL.path) {
            try? fileManager.removeItem(at: manifestURL)
        }
    }

    private func removeFilesReferenced(
        by oldManifest: PanelBackgroundManifest?,
        excluding newManifest: PanelBackgroundManifest?
    ) {
        let retainedPaths = Set(
            Self.urlsReferenced(by: newManifest, directoryURL: directoryURL).map(\.path)
        )
        for url in Self.urlsReferenced(by: oldManifest, directoryURL: directoryURL)
        where !retainedPaths.contains(url.path) && fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
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

    private static func loadManifestAsset(
        from manifestURL: URL,
        directoryURL: URL,
        fileManager: FileManager
    ) -> PanelBackgroundAsset? {
        guard let manifest = loadManifest(from: manifestURL, fileManager: fileManager),
              manifest.schemaVersion == PanelBackgroundManifest.currentSchemaVersion,
              isSafeFilename(manifest.mediaFilename) else {
            return nil
        }

        let mediaURL = directoryURL.appendingPathComponent(manifest.mediaFilename)
        guard fileManager.fileExists(atPath: mediaURL.path) else { return nil }
        let imageURL: URL
        switch manifest.kind {
        case .staticImage:
            imageURL = mediaURL
        case .convertedGIF, .video:
            guard let posterFilename = manifest.posterFilename,
                  isSafeFilename(posterFilename) else {
                return nil
            }
            imageURL = directoryURL.appendingPathComponent(posterFilename)
        }
        guard fileManager.fileExists(atPath: imageURL.path),
              let posterImage = loadImage(at: imageURL) else {
            return nil
        }
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
        return try? JSONDecoder().decode(PanelBackgroundManifest.self, from: data)
    }

    private static func urlsReferenced(
        by manifest: PanelBackgroundManifest?,
        directoryURL: URL
    ) -> [URL] {
        guard let manifest else { return [] }
        return [manifest.mediaFilename, manifest.posterFilename]
            .compactMap { $0 }
            .filter(isSafeFilename)
            .map { directoryURL.appendingPathComponent($0) }
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && filename != "."
            && filename != ".."
    }

    private static func loadLegacyAsset(at url: URL) -> PanelBackgroundAsset? {
        guard let image = loadImage(at: url) else { return nil }
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
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix("staging-") {
            let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            if isDirectory == true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static let legacyAssetID = "legacy-background.png"
}
