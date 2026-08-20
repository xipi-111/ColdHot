@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

struct PanelBackgroundPreparedImport {
    let kind: PanelBackgroundMediaKind
    let mediaURL: URL
    let posterURL: URL?
    let originalTypeIdentifier: String
    let hasAudio: Bool
}

enum PanelBackgroundImportError: LocalizedError {
    case gifTooLarge
    case videoTooLarge
    case unreadableMedia
    case missingVideoTrack
    case unsupportedVideo
    case gifConversionFailed
    case unableToCreatePoster
    case unableToWrite
    case operationInProgress
    case rollbackFailed
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .gifTooLarge:
            "GIF 文件超过 100 MB，未更换当前背景。"
        case .videoTooLarge:
            "视频文件超过 1 GB，未更换当前背景。"
        case .unreadableMedia:
            "无法读取所选文件，请确认文件未损坏。"
        case .missingVideoTrack:
            "所选文件不包含视频轨道。"
        case .unsupportedVideo:
            "当前 Mac 无法播放这个视频或其编码格式。"
        case .gifConversionFailed:
            "无法转换这个 GIF，请选择其他文件。"
        case .unableToCreatePoster:
            "无法从动态背景生成静态封面。"
        case .unableToWrite:
            "无法写入背景文件，请检查本地存储空间后重试。"
        case .operationInProgress:
            "另一项背景操作正在进行，请稍后重试。"
        case .rollbackFailed:
            "背景操作失败，且部分临时文件无法清理。当前背景仍保持可用。"
        case .cleanupFailed:
            "背景已更新，但旧背景文件未能完全清理。"
        }
    }
}

struct PanelBackgroundMediaImporter {
    static let maximumPixelDimension = 1_600

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareImport(
        from sourceURL: URL,
        in stagingDirectory: URL
    ) async throws -> PanelBackgroundPreparedImport {
        try Task.checkCancellation()
        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }

        let byteCount = try fileSize(at: sourceURL)
        guard let resolvedType = resolvedMediaType(at: sourceURL) else {
            throw PanelBackgroundImportError.unreadableMedia
        }

        switch resolvedType.category {
        case .gif:
            guard PanelBackgroundImportLimits.acceptsGIF(byteCount: byteCount) else {
                throw PanelBackgroundImportError.gifTooLarge
            }
            return try await prepareGIF(
                from: sourceURL,
                typeIdentifier: resolvedType.type.identifier,
                in: stagingDirectory
            )
        case .video:
            guard PanelBackgroundImportLimits.acceptsVideo(byteCount: byteCount) else {
                throw PanelBackgroundImportError.videoTooLarge
            }
            return try await prepareVideo(
                from: sourceURL,
                type: resolvedType.type,
                expectedByteCount: byteCount,
                in: stagingDirectory
            )
        case .image:
            let mediaURL = stagingDirectory.appendingPathComponent("media.png")
            try Self.writeStaticThumbnail(from: sourceURL, to: mediaURL)
            return PanelBackgroundPreparedImport(
                kind: .staticImage,
                mediaURL: mediaURL,
                posterURL: nil,
                originalTypeIdentifier: resolvedType.type.identifier,
                hasAudio: false
            )
        }
    }

    static func writeStaticThumbnail(from sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw PanelBackgroundImportError.unreadableMedia
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw PanelBackgroundImportError.unreadableMedia
        }
        try writePNG(thumbnail, to: destinationURL)
    }

    private func prepareGIF(
        from sourceURL: URL,
        typeIdentifier: String,
        in stagingDirectory: URL
    ) async throws -> PanelBackgroundPreparedImport {
        let mediaURL = stagingDirectory.appendingPathComponent("media.mp4")
        do {
            _ = try await GIFVideoConverter().convert(
                sourceURL: sourceURL,
                destinationURL: mediaURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PanelBackgroundImportError.gifConversionFailed
        }

        let posterURL = stagingDirectory.appendingPathComponent("poster.png")
        do {
            try await makeVideoPoster(from: mediaURL, at: posterURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PanelBackgroundImportError.unableToCreatePoster
        }
        return PanelBackgroundPreparedImport(
            kind: .convertedGIF,
            mediaURL: mediaURL,
            posterURL: posterURL,
            originalTypeIdentifier: typeIdentifier,
            hasAudio: false
        )
    }

    private func prepareVideo(
        from sourceURL: URL,
        type: UTType,
        expectedByteCount: Int64,
        in stagingDirectory: URL
    ) async throws -> PanelBackgroundPreparedImport {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let isPlayable: Bool
        do {
            isPlayable = try await sourceAsset.load(.isPlayable)
        } catch {
            try Self.rethrowVideoLoadError(error)
        }
        try Task.checkCancellation()
        guard isPlayable else {
            throw PanelBackgroundImportError.unsupportedVideo
        }

        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        } catch {
            try Self.rethrowVideoLoadError(error)
        }
        guard !videoTracks.isEmpty else {
            throw PanelBackgroundImportError.missingVideoTrack
        }
        try Task.checkCancellation()

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? (type.preferredFilenameExtension ?? "mov")
            : sourceURL.pathExtension
        let mediaURL = stagingDirectory.appendingPathComponent("media.\(fileExtension)")
        try materializeRegularFile(
            from: sourceURL,
            to: mediaURL,
            expectedByteCount: expectedByteCount
        )

        let posterURL = stagingDirectory.appendingPathComponent("poster.png")
        do {
            try await makeVideoPoster(from: mediaURL, at: posterURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PanelBackgroundImportError.unableToCreatePoster
        }
        return PanelBackgroundPreparedImport(
            kind: .video,
            mediaURL: mediaURL,
            posterURL: posterURL,
            originalTypeIdentifier: type.identifier,
            hasAudio: !audioTracks.isEmpty
        )
    }

    private func makeVideoPoster(from mediaURL: URL, at destinationURL: URL) async throws {
        try Task.checkCancellation()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: mediaURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: Self.maximumPixelDimension,
            height: Self.maximumPixelDimension
        )
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, actualTime) = try await generator.image(at: .zero)
        guard CMTimeCompare(actualTime, .zero) == 0 else {
            throw PanelBackgroundImportError.unableToCreatePoster
        }
        try Self.writePNG(image, to: destinationURL)
    }

    static func rethrowVideoLoadError(_ error: Error) throws -> Never {
        if error is CancellationError {
            throw CancellationError()
        }
        throw PanelBackgroundImportError.unreadableMedia
    }

    private func materializeRegularFile(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedByteCount: Int64
    ) throws {
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw PanelBackgroundImportError.unableToWrite
        }
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: destinationURL)
            }
        }

        do {
            let source = try FileHandle(forReadingFrom: sourceURL)
            let destination = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? source.close()
                try? destination.close()
            }
            var copiedByteCount: Int64 = 0
            while let data = try source.read(upToCount: 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                copiedByteCount += Int64(data.count)
                guard PanelBackgroundImportLimits.acceptsVideo(byteCount: copiedByteCount) else {
                    throw PanelBackgroundImportError.videoTooLarge
                }
                try destination.write(contentsOf: data)
            }
            guard copiedByteCount == expectedByteCount else {
                throw PanelBackgroundImportError.unreadableMedia
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PanelBackgroundImportError {
            throw error
        } catch {
            throw PanelBackgroundImportError.unableToWrite
        }
        completed = true
    }

    private static func writePNG(_ image: CGImage, to destinationURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PanelBackgroundImportError.unableToWrite
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PanelBackgroundImportError.unableToWrite
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(
                atPath: url.resolvingSymlinksInPath().path
            )
        } catch {
            throw PanelBackgroundImportError.unreadableMedia
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let byteCount = (attributes[.size] as? NSNumber)?.int64Value else {
            throw PanelBackgroundImportError.unreadableMedia
        }
        return byteCount
    }

    private func resolvedMediaType(at url: URL) -> ResolvedMediaType? {
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let extensionType = UTType(filenameExtension: url.pathExtension)

        for type in [resourceType, extensionType].compactMap({ $0 }) {
            if type.conforms(to: .gif) {
                return ResolvedMediaType(type: type, category: .gif)
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return ResolvedMediaType(type: type, category: .video)
            }
            if type.conforms(to: .image) {
                return ResolvedMediaType(type: type, category: .image)
            }
        }
        if hasGIFSignature(at: url) {
            return ResolvedMediaType(type: .gif, category: .gif)
        }
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let typeIdentifier = CGImageSourceGetType(source),
              let type = UTType(typeIdentifier as String),
              type.conforms(to: .image) else {
            return nil
        }
        return ResolvedMediaType(
            type: type,
            category: type.conforms(to: .gif) ? .gif : .image
        )
    }

    private func hasGIFSignature(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 6), data.count == 6 else {
            return false
        }
        return data == Data("GIF87a".utf8) || data == Data("GIF89a".utf8)
    }
}

private struct ResolvedMediaType {
    enum Category {
        case image
        case gif
        case video
    }

    let type: UTType
    let category: Category
}
