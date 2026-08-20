import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

@main
enum GIFVideoConversionCheck {
    static func main() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ColdHot-GIFVideoConversionCheck-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        if let selectedCheck = CommandLine.arguments.dropFirst().first {
            try await run(selectedCheck, in: directory)
            print("GIF video conversion check passed: \(selectedCheck)")
        } else {
            for check in [
                "timing",
                "delays",
                "limits",
                "scaling",
                "transparency",
                "cancellation",
                "writer-failure",
                "invalid-input",
            ] {
                try await run(check, in: directory)
            }
            print("GIF video conversion checks passed")
        }
    }

    private static func run(_ name: String, in directory: URL) async throws {
        switch name {
        case "timing":
            try await checkTimingColorPlayabilityAndAudio(in: directory)
        case "delays":
            checkDelaySelectionAndMinimum()
        case "limits":
            try await checkExactGIFLimitAcceptedAndOneByteOverRejected(in: directory)
        case "scaling":
            try await checkMaximumDimensionScaling(in: directory)
        case "transparency":
            try await checkTransparentCompositingBackgrounds(in: directory)
        case "cancellation":
            try await checkCancellationCleansPartialOutput(in: directory)
        case "writer-failure":
            try await checkWriterFailureCleansOutput(in: directory)
        case "invalid-input":
            try await checkInvalidInputCleansOutput(in: directory)
        default:
            preconditionFailure("Unknown check: \(name)")
        }
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
        let assetDuration = try await asset.load(.duration)
        precondition(videoTracks.count == 1)
        precondition(audioTracks.isEmpty)
        precondition(isPlayable)
        precondition(
            abs(assetDuration.seconds - 0.35) < 0.06,
            "Encoded asset duration must include the final 0.25-second frame delay; got \(assetDuration.seconds)"
        )
        let trackTimeRange = try await videoTracks[0].load(.timeRange)
        precondition(
            abs(trackTimeRange.duration.seconds - 0.35) < 0.06,
            "Encoded track duration must include the final 0.25-second frame delay; got \(trackTimeRange.duration.seconds)"
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let first = try await generator.image(at: CMTime(seconds: 0.03, preferredTimescale: 600)).image
        let second = try await generator.image(at: CMTime(seconds: 0.20, preferredTimescale: 600)).image
        let nearEnd = try await generator.image(at: CMTime(seconds: 0.33, preferredTimescale: 600)).image
        let firstColor = try averageColor(of: first)
        let secondColor = try averageColor(of: second)
        let nearEndColor = try averageColor(of: nearEnd)

        precondition(firstColor.red > firstColor.blue * 2)
        precondition(secondColor.blue > secondColor.red * 2)
        precondition(nearEndColor.blue > nearEndColor.red * 2)
    }

    private static func checkDelaySelectionAndMinimum() {
        let precedence = GIFVideoConverter.frameDuration(
            unclampedDelay: 0.10,
            clampedDelay: 0.25
        )
        precondition(
            abs(precedence.seconds - 0.10) < 0.001,
            "Unclamped delay must take precedence over clamped delay"
        )

        let clampedFallback = GIFVideoConverter.frameDuration(
            unclampedDelay: nil,
            clampedDelay: 0.25
        )
        precondition(
            abs(clampedFallback.seconds - 0.25) < 0.001,
            "Clamped delay must be used when unclamped delay is absent"
        )

        let invalidSelections: [CMTime] = [
            GIFVideoConverter.frameDuration(unclampedDelay: nil, clampedDelay: nil),
            GIFVideoConverter.frameDuration(unclampedDelay: .nan, clampedDelay: 0.25),
            GIFVideoConverter.frameDuration(unclampedDelay: nil, clampedDelay: 0),
            GIFVideoConverter.frameDuration(unclampedDelay: nil, clampedDelay: -0.5),
        ]
        precondition(
            invalidSelections.allSatisfy { abs($0.seconds - 0.02) < 0.001 },
            "Missing, non-finite, zero, and negative delays must become 0.02 seconds"
        )
    }

    private static func checkExactGIFLimitAcceptedAndOneByteOverRejected(
        in directory: URL
    ) async throws {
        let exactURL = directory.appendingPathComponent("exact-limit.gif")
        let exactOutputURL = directory.appendingPathComponent("exact-limit.mp4")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: exactURL)
        try DynamicBackgroundTestMedia.extendFile(
            at: exactURL,
            toByteCount: PanelBackgroundImportLimits.maximumGIFBytes
        )

        let exactResult = try await GIFVideoConverter().convert(
            sourceURL: exactURL,
            destinationURL: exactOutputURL
        )
        precondition(exactResult.frameCount == 2, "A GIF exactly at 100 MB must be accepted")

        let overURL = directory.appendingPathComponent("over-limit.gif")
        let overOutputURL = directory.appendingPathComponent("over-limit.mp4")
        try DynamicBackgroundTestMedia.makeTwoFrameGIF(at: overURL)
        try DynamicBackgroundTestMedia.extendFile(
            at: overURL,
            toByteCount: PanelBackgroundImportLimits.maximumGIFBytes + 1
        )

        do {
            _ = try await GIFVideoConverter().convert(
                sourceURL: overURL,
                destinationURL: overOutputURL
            )
            preconditionFailure("A GIF one byte over 100 MB must be rejected")
        } catch {
            precondition(!FileManager.default.fileExists(atPath: overOutputURL.path))
        }
    }

    private static func checkMaximumDimensionScaling(in directory: URL) async throws {
        let sourceURL = directory.appendingPathComponent("oversized.gif")
        let outputURL = directory.appendingPathComponent("oversized.mp4")
        try DynamicBackgroundTestMedia.makeOversizedTwoFrameGIF(at: sourceURL)

        let result = try await GIFVideoConverter().convert(
            sourceURL: sourceURL,
            destinationURL: outputURL
        )
        precondition(
            result.displaySize == CGSize(width: 1_600, height: 800),
            "A 2,000×1,000 GIF must scale to 1,600×800"
        )

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        precondition(tracks.count == 1)
        let naturalSize = try await tracks[0].load(.naturalSize)
        precondition(naturalSize == CGSize(width: 1_600, height: 800))

        let image = try await decodedImage(at: 0.03, from: asset)
        precondition(image.width == 1_600 && image.height == 800)
    }

    private static func checkTransparentCompositingBackgrounds(in directory: URL) async throws {
        let logicalSourceURL = directory.appendingPathComponent("logical-background.gif")
        let logicalOutputURL = directory.appendingPathComponent("logical-background.mp4")
        try DynamicBackgroundTestMedia.makeTransparentGIFWithLogicalBackground(at: logicalSourceURL)
        _ = try await GIFVideoConverter().convert(
            sourceURL: logicalSourceURL,
            destinationURL: logicalOutputURL
        )
        let logicalImage = try await decodedImage(
            at: 0.03,
            from: AVURLAsset(url: logicalOutputURL)
        )
        let logicalPixel = try pixelColor(of: logicalImage, x: 4, y: 12)
        precondition(
            logicalPixel.green > logicalPixel.red * 2
                && logicalPixel.green > logicalPixel.blue * 2
                && logicalPixel.green > 100,
            "Transparent pixels must use the GIF logical green background"
        )

        let blackSourceURL = directory.appendingPathComponent("missing-background.gif")
        let blackOutputURL = directory.appendingPathComponent("missing-background.mp4")
        try DynamicBackgroundTestMedia.makeTransparentGIFWithoutLogicalBackground(at: blackSourceURL)
        _ = try await GIFVideoConverter().convert(
            sourceURL: blackSourceURL,
            destinationURL: blackOutputURL
        )
        let blackImage = try await decodedImage(at: 0.03, from: AVURLAsset(url: blackOutputURL))
        let blackPixel = try pixelColor(of: blackImage, x: 4, y: 12)
        precondition(
            blackPixel.red < 50 && blackPixel.green < 50 && blackPixel.blue < 50,
            "Transparent pixels without a logical background must use black"
        )
    }

    private static func checkCancellationCleansPartialOutput(in directory: URL) async throws {
        let sourceURL = directory.appendingPathComponent("cancellation.gif")
        let outputURL = directory.appendingPathComponent("cancellation.mp4")
        try DynamicBackgroundTestMedia.makeCancellationGIF(at: sourceURL)

        let task = Task {
            try await GIFVideoConverter().convert(
                sourceURL: sourceURL,
                destinationURL: outputURL
            )
        }
        defer { task.cancel() }

        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: outputURL.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        precondition(
            FileManager.default.fileExists(atPath: outputURL.path),
            "Cancellation fixture must reach a partially created output"
        )

        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("A mid-conversion cancellation must throw")
        } catch {
            precondition(
                !FileManager.default.fileExists(atPath: outputURL.path),
                "Cancellation must remove the partial MP4"
            )
        }
    }

    private static func checkWriterFailureCleansOutput(in directory: URL) async throws {
        let outputURL = directory.appendingPathComponent("writer-failure.mp4")

        do {
            try await GIFVideoConverter.withIncompleteOutputCleanup(at: outputURL) {
                try await makeRealWriterFailWithPartialOutput(at: outputURL)
            }
            preconditionFailure("The out-of-order writer fixture must fail")
        } catch {
            precondition(
                !FileManager.default.fileExists(atPath: outputURL.path),
                "A failed writer must leave no partial MP4"
            )
        }
    }

    private static func makeRealWriterFailWithPartialOutput(at outputURL: URL) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 32,
                AVVideoHeightKey: 24,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 32,
                kCVPixelBufferHeightKey as String: 24,
            ]
        )
        precondition(writer.canAdd(input))
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw CheckError.unableToCreatePixelBuffer
        }
        var optionalPixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalPixelBuffer) == kCVReturnSuccess,
              let pixelBuffer = optionalPixelBuffer else {
            throw CheckError.unableToCreatePixelBuffer
        }
        precondition(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: 60, timescale: 600)))
        precondition(FileManager.default.fileExists(atPath: outputURL.path))

        precondition(adaptor.append(pixelBuffer, withPresentationTime: .zero))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        precondition(writer.status == .failed, "Out-of-order timestamps must fail the real writer")
        throw writer.error ?? CheckError.writerDidNotFail
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

    private static func decodedImage(at seconds: Double, from asset: AVAsset) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)
        ).image
    }

    private static func pixelColor(
        of image: CGImage,
        x: Int,
        y: Int
    ) throws -> (red: Double, green: Double, blue: Double) {
        precondition(x >= 0 && x < image.width && y >= 0 && y < image.height)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }

        guard rendered else { throw CheckError.unableToReadPixel }
        let offset = (y * image.width + x) * 4
        return (
            Double(pixels[offset]),
            Double(pixels[offset + 1]),
            Double(pixels[offset + 2])
        )
    }
}

private enum CheckError: Error {
    case unableToReadPixel
    case unableToCreatePixelBuffer
    case writerDidNotFail
}
