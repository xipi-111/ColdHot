import AVFoundation
import CoreGraphics
import Foundation

@main
enum GIFVideoConversionCheck {
    static func main() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ColdHot-GIFVideoConversionCheck-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try await checkTimingColorPlayabilityAndAudio(in: directory)
        try await checkInvalidInputCleansOutput(in: directory)
        print("GIF video conversion checks passed")
    }

    private static func checkTimingColorPlayabilityAndAudio(in directory: URL) async throws {
        let gifURL = directory.appendingPathComponent("two-frame.gif")
        let mp4URL = directory.appendingPathComponent("two-frame.mp4")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: gifURL)

        let result = try await GIFVideoConverter().convert(
            sourceURL: gifURL,
            destinationURL: mp4URL
        )

        precondition(result.frameCount == 2)
        precondition(abs(result.duration.seconds - 0.35) < 0.06)
        precondition(result.displaySize == CGSize(width: 32, height: 24))

        let asset = AVURLAsset(url: mp4URL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let isPlayable = try await asset.load(.isPlayable)
        precondition(videoTracks.count == 1)
        precondition(audioTracks.isEmpty)
        precondition(isPlayable)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let first = try await generator.image(at: CMTime(seconds: 0.03, preferredTimescale: 600)).image
        let second = try await generator.image(at: CMTime(seconds: 0.20, preferredTimescale: 600)).image
        let firstColor = try averageColor(of: first)
        let secondColor = try averageColor(of: second)

        precondition(firstColor.red > firstColor.blue * 2)
        precondition(secondColor.blue > secondColor.red * 2)
    }

    private static func checkInvalidInputCleansOutput(in directory: URL) async throws {
        let invalidURL = directory.appendingPathComponent("invalid.gif")
        let outputURL = directory.appendingPathComponent("invalid.mp4")
        try Data("not a gif".utf8).write(to: invalidURL)

        do {
            _ = try await GIFVideoConverter().convert(
                sourceURL: invalidURL,
                destinationURL: outputURL
            )
            preconditionFailure("Invalid GIF unexpectedly converted")
        } catch {
            precondition(!FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    private static func averageColor(of image: CGImage) throws -> (red: Double, green: Double, blue: Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        guard rendered else { throw CheckError.unableToReadPixel }
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }
}

private enum CheckError: Error {
    case unableToReadPixel
}
