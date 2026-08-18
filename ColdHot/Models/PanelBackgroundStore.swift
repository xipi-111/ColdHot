import Foundation
import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

enum PanelBackgroundStoreError: LocalizedError {
    case unreadableImage
    case unableToEncodeImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "无法读取这张图片，请选择有效的 PNG、JPEG、HEIC 或 TIFF 图片。"
        case .unableToEncodeImage:
            "无法保存背景图片，请稍后重试。"
        }
    }
}

@MainActor
final class PanelBackgroundStore: ObservableObject {
    static let maximumPixelDimension = 1_600

    @Published private(set) var image: NSImage?

    let fileURL: URL

    var hasImage: Bool { image != nil }

    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let resolvedDirectory = directoryURL
            ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.directoryURL = resolvedDirectory
        fileURL = resolvedDirectory.appendingPathComponent("background.png")
        image = Self.loadImage(at: fileURL)
    }

    func importImage(from sourceURL: URL) throws {
        let isAccessingSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw PanelBackgroundStoreError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw PanelBackgroundStoreError.unreadableImage
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PanelBackgroundStoreError.unableToEncodeImage
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PanelBackgroundStoreError.unableToEncodeImage
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try (encodedData as Data).write(to: fileURL, options: .atomic)
        image = Self.makeImage(from: thumbnail)
    }

    func removeImage() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        image = nil
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

    private static func loadImage(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return nil
        }
        return makeImage(from: image)
    }

    private static func makeImage(from image: CGImage) -> NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }
}
