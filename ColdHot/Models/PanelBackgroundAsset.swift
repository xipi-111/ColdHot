import AppKit
import Foundation

enum PanelBackgroundMediaKind: String, Codable, Equatable {
    case staticImage, convertedGIF, video

    var isDynamic: Bool { self != .staticImage }
}

enum PanelBackgroundPosterPolicy {
    static func showsPoster(
        mediaKind: PanelBackgroundMediaKind,
        reduceMotion: Bool
    ) -> Bool {
        !mediaKind.isDynamic || reduceMotion
    }
}

struct DynamicBackgroundRevealState: Equatable {
    static let revealDuration: TimeInterval = 0.4

    private(set) var isReadyForDisplay = false

    var maskOpacity: Double { isReadyForDisplay ? 0 : 1 }
    var animationDuration: TimeInterval {
        isReadyForDisplay ? Self.revealDuration : 0
    }

    mutating func receive(isReadyForDisplay: Bool) {
        self.isReadyForDisplay = isReadyForDisplay
    }

    mutating func reset() {
        isReadyForDisplay = false
    }
}

struct PanelBackgroundManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generationID: String
    let kind: PanelBackgroundMediaKind
    let mediaFilename: String
    let posterFilename: String?
    let originalTypeIdentifier: String
    let hasAudio: Bool
}

struct PanelBackgroundAsset: Identifiable {
    let id: String
    let kind: PanelBackgroundMediaKind
    let posterImage: NSImage
    let mediaURL: URL?
    let hasAudio: Bool

    var isDynamic: Bool { kind.isDynamic }
}

enum PanelBackgroundImportLimits {
    static let maximumGIFBytes: Int64 = 100 * 1_024 * 1_024
    static let maximumVideoBytes: Int64 = 1_024 * 1_024 * 1_024

    static func acceptsGIF(byteCount: Int64) -> Bool {
        byteCount >= 0 && byteCount <= maximumGIFBytes
    }

    static func acceptsVideo(byteCount: Int64) -> Bool {
        byteCount >= 0 && byteCount <= maximumVideoBytes
    }
}
