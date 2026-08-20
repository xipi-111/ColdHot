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

        guard let resolvedType = resolvedMediaType(at: sourceURL) else {
            throw PanelBackgroundImportError.unreadableMedia
        }
        let byteCount = try fileSize(at: sourceURL)

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
        in stagingDirectory: URL
    ) async throws -> PanelBackgroundPreparedImport {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let isPlayable: Bool
        do {
            isPlayable = try await sourceAsset.load(.isPlayable)
        } catch {
            throw PanelBackgroundImportError.unreadableMedia
        }
        guard isPlayable else {
            throw PanelBackgroundImportError.unsupportedVideo
        }

        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        } catch {
            throw PanelBackgroundImportError.unreadableMedia
        }
        guard !videoTracks.isEmpty else {
            throw PanelBackgroundImportError.missingVideoTrack
        }
        try Task.checkCancellation()

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? (type.preferredFilenameExtension ?? "mov")
            : sourceURL.pathExtension
        let mediaURL = stagingDirectory.appendingPathComponent("media.\(fileExtension)")
        do {
            try fileManager.copyItem(at: sourceURL, to: mediaURL)
        } catch {
            throw PanelBackgroundImportError.unableToWrite
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
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let (image, _) = try await generator.image(at: .zero)
        try Self.writePNG(image, to: destinationURL)
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
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw PanelBackgroundImportError.unreadableMedia
        }
        guard let byteCount = (attributes[.size] as? NSNumber)?.int64Value else {
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
