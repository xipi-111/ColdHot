@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ImageIO

struct GIFVideoConversionResult {
    let frameCount: Int
    let duration: CMTime
    let displaySize: CGSize
}

struct GIFVideoConverter {
    static let maximumPixelDimension = 1_600
    static let minimumFrameDuration = 0.02

    static func frameDuration(
        unclampedDelay: Double?,
        clampedDelay: Double?
    ) -> CMTime {
        let delay = unclampedDelay ?? clampedDelay
        let validDelay = if let delay, delay.isFinite, delay > 0 {
            delay
        } else {
            minimumFrameDuration
        }
        return CMTime(seconds: validDelay, preferredTimescale: 600)
    }

    func convert(sourceURL: URL, destinationURL: URL) async throws -> GIFVideoConversionResult {
        try Task.checkCancellation()
        try validateInputLimit(at: sourceURL)

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw GIFVideoConversionError.destinationAlreadyExists
        }

        return try await Self.withIncompleteOutputCleanup(at: destinationURL) {
            try await convertValidatedGIF(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        }
    }

    private func convertValidatedGIF(
        sourceURL: URL,
        destinationURL: URL
    ) async throws -> GIFVideoConversionResult {
        guard
            let source = CGImageSourceCreateWithURL(
                sourceURL as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetCount(source) > 0
        else {
            throw GIFVideoConversionError.unreadableGIF
        }

        let frameCount = CGImageSourceGetCount(source)
        let canvasSize = try canvasSize(for: source)
        let contentSize = scaledSize(for: canvasSize)
        let displaySize = encoderSafeSize(for: contentSize)
        let delays = (0..<frameCount).map { frameDuration(at: $0, in: source) }
        let duration = delays.reduce(CMTime.zero, CMTimeAdd)
        let backgroundColor = logicalBackgroundColor(at: sourceURL) ?? CGColor.black

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        } catch {
            throw GIFVideoConversionError.couldNotCreateWriter(error)
        }

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(displaySize.width),
            AVVideoHeightKey: Int(displaySize.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(displaySize.width),
            kCVPixelBufferHeightKey as String: Int(displaySize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(input) else {
            throw GIFVideoConversionError.couldNotConfigureWriter
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw GIFVideoConversionError.writerFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        do {
            try await appendFrames(
                from: source,
                frameCount: frameCount,
                delays: delays,
                contentSize: contentSize,
                displaySize: displaySize,
                backgroundColor: backgroundColor,
                writer: writer,
                input: input,
                adaptor: adaptor
            )
            try Task.checkCancellation()
            writer.endSession(atSourceTime: duration)
            try await finishWriting(writer)
        } catch {
            writer.cancelWriting()
            throw error
        }

        guard writer.status == .completed else {
            throw GIFVideoConversionError.writerFailed(writer.error)
        }

        return GIFVideoConversionResult(
            frameCount: frameCount,
            duration: duration,
            displaySize: displaySize
        )
    }

    static func withIncompleteOutputCleanup<Value>(
        at destinationURL: URL,
        operation: () async throws -> Value
    ) async throws -> Value {
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }

        let value = try await operation()
        completed = true
        return value
    }

    private func validateInputLimit(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
            throw GIFVideoConversionError.unreadableGIF
        }
        guard PanelBackgroundImportLimits.acceptsGIF(byteCount: fileSize) else {
            throw GIFVideoConversionError.gifTooLarge
        }
    }

    private func canvasSize(for source: CGImageSource) throws -> CGSize {
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let width = numericValue(gifProperties?[kCGImagePropertyGIFCanvasPixelWidth])
            ?? numericValue(properties?[kCGImagePropertyPixelWidth])
        let height = numericValue(gifProperties?[kCGImagePropertyGIFCanvasPixelHeight])
            ?? numericValue(properties?[kCGImagePropertyPixelHeight])

        if let width, let height, width > 0, height > 0 {
            return CGSize(width: width, height: height)
        }

        guard let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GIFVideoConversionError.unreadableGIF
        }
        return CGSize(width: firstImage.width, height: firstImage.height)
    }

    private func scaledSize(for canvasSize: CGSize) -> CGSize {
        let maximumEdge = max(canvasSize.width, canvasSize.height)
        let scale = min(1, CGFloat(Self.maximumPixelDimension) / maximumEdge)
        return CGSize(
            width: max(1, (canvasSize.width * scale).rounded()),
            height: max(1, (canvasSize.height * scale).rounded())
        )
    }

    private func encoderSafeSize(for contentSize: CGSize) -> CGSize {
        CGSize(
            width: encoderSafeDimension(contentSize.width),
            height: encoderSafeDimension(contentSize.height)
        )
    }

    private func encoderSafeDimension(_ dimension: CGFloat) -> CGFloat {
        let integerDimension = max(2, Int(dimension.rounded(.up)))
        return CGFloat(
            integerDimension.isMultiple(of: 2)
                ? integerDimension
                : integerDimension + 1
        )
    }

    private func frameDuration(at index: Int, in source: CGImageSource) -> CMTime {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return Self.frameDuration(
            unclampedDelay: numericValue(gifProperties?[kCGImagePropertyGIFUnclampedDelayTime]),
            clampedDelay: numericValue(gifProperties?[kCGImagePropertyGIFDelayTime])
        )
    }

    private func numericValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func appendFrames(
        from source: CGImageSource,
        frameCount: Int,
        delays: [CMTime],
        contentSize: CGSize,
        displaySize: CGSize,
        backgroundColor: CGColor,
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        let completion = OneShotContinuation()
        let progress = AppendProgress()
        let queue = DispatchQueue(label: "com.xipiyoung.ColdHot.gif-video-writer")
        let sourceBox = UncheckedSendable(source)
        let writerBox = UncheckedSendable(writer)
        let inputBox = UncheckedSendable(input)
        let adaptorBox = UncheckedSendable(adaptor)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                completion.performIfNotFinished {
                    input.requestMediaDataWhenReady(on: queue) {
                        guard !completion.isFinished else { return }

                        do {
                            while inputBox.value.isReadyForMoreMediaData {
                                guard !completion.isFinished else { return }
                                guard writerBox.value.status == .writing else {
                                    throw GIFVideoConversionError.writerFailed(writerBox.value.error)
                                }

                                if progress.frameIndex < frameCount {
                                    let image = try autoreleasepool {
                                        guard let image = CGImageSourceCreateImageAtIndex(
                                            sourceBox.value,
                                            progress.frameIndex,
                                            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                                        ) else {
                                            throw GIFVideoConversionError.unreadableFrame(progress.frameIndex)
                                        }
                                        let pixelBuffer = try makePixelBuffer(
                                            for: image,
                                            contentSize: contentSize,
                                            displaySize: displaySize,
                                            backgroundColor: backgroundColor,
                                            pool: adaptorBox.value.pixelBufferPool
                                        )
                                        guard adaptorBox.value.append(
                                            pixelBuffer,
                                            withPresentationTime: progress.presentationTime
                                        ) else {
                                            throw GIFVideoConversionError.writerFailed(writerBox.value.error)
                                        }
                                        return image
                                    }
                                    progress.lastImage = image
                                    progress.presentationTime = CMTimeAdd(
                                        progress.presentationTime,
                                        delays[progress.frameIndex]
                                    )
                                    progress.frameIndex += 1
                                } else if !progress.didAppendFinalFrame {
                                    guard let lastImage = progress.lastImage else {
                                        throw GIFVideoConversionError.unreadableGIF
                                    }
                                    let pixelBuffer = try makePixelBuffer(
                                        for: lastImage,
                                        contentSize: contentSize,
                                        displaySize: displaySize,
                                        backgroundColor: backgroundColor,
                                        pool: adaptorBox.value.pixelBufferPool
                                    )
                                    guard adaptorBox.value.append(
                                        pixelBuffer,
                                        withPresentationTime: progress.presentationTime
                                    ) else {
                                        throw GIFVideoConversionError.writerFailed(writerBox.value.error)
                                    }
                                    progress.didAppendFinalFrame = true
                                } else {
                                    inputBox.value.markAsFinished()
                                    completion.finish(with: .success(()))
                                    return
                                }
                            }
                        } catch {
                            completion.finish(with: .failure(error))
                        }
                    }
                }
            }
        } onCancel: {
            completion.finish(with: .failure(CancellationError()))
            writerBox.value.cancelWriting()
        }
    }

    private func makePixelBuffer(
        for image: CGImage,
        contentSize: CGSize,
        displaySize: CGSize,
        backgroundColor: CGColor,
        pool: CVPixelBufferPool?
    ) throws -> CVPixelBuffer {
        guard let pool else {
            throw GIFVideoConversionError.couldNotCreatePixelBuffer
        }

        var optionalPixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalPixelBuffer) == kCVReturnSuccess,
              let pixelBuffer = optionalPixelBuffer else {
            throw GIFVideoConversionError.couldNotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            throw GIFVideoConversionError.couldNotCreatePixelBuffer
        }

        let bounds = CGRect(origin: .zero, size: displaySize)
        context.setBlendMode(.copy)
        context.setFillColor(backgroundColor)
        context.fill(bounds)
        context.setBlendMode(.normal)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: contentSize))
        return pixelBuffer
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let completion = OneShotContinuation()
        let writerBox = UncheckedSendable(writer)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                completion.performIfNotFinished {
                    writer.finishWriting {
                        guard writerBox.value.status == .completed else {
                            completion.finish(
                                with: .failure(GIFVideoConversionError.writerFailed(writerBox.value.error))
                            )
                            return
                        }
                        completion.finish(with: .success(()))
                    }
                }
            }
        } onCancel: {
            completion.finish(with: .failure(CancellationError()))
            writerBox.value.cancelWriting()
        }
    }

    private func logicalBackgroundColor(at url: URL) -> CGColor? {
        guard
            let handle = try? FileHandle(forReadingFrom: url),
            let data = try? handle.read(upToCount: 13 + 256 * 3),
            data.count >= 13
        else {
            return nil
        }
        try? handle.close()

        let bytes = [UInt8](data)
        guard String(bytes: bytes[0..<6], encoding: .ascii)?.hasPrefix("GIF") == true else {
            return nil
        }

        let packedFields = bytes[10]
        guard packedFields & 0x80 != 0 else { return nil }
        let colorCount = 1 << (Int(packedFields & 0x07) + 1)
        let backgroundIndex = Int(bytes[11])
        guard backgroundIndex < colorCount else { return nil }

        let colorOffset = 13 + backgroundIndex * 3
        guard bytes.count >= colorOffset + 3 else { return nil }
        return CGColor(
            red: CGFloat(bytes[colorOffset]) / 255,
            green: CGFloat(bytes[colorOffset + 1]) / 255,
            blue: CGFloat(bytes[colorOffset + 2]) / 255,
            alpha: 1
        )
    }
}

private final class AppendProgress: @unchecked Sendable {
    var frameIndex = 0
    var presentationTime = CMTime.zero
    var lastImage: CGImage?
    var didAppendFinalFrame = false
}

private final class UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class OneShotContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(with result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func performIfNotFinished(_ operation: () -> Void) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        operation()
        lock.unlock()
    }
}

private enum GIFVideoConversionError: LocalizedError {
    case gifTooLarge
    case destinationAlreadyExists
    case unreadableGIF
    case unreadableFrame(Int)
    case couldNotCreateWriter(Error)
    case couldNotConfigureWriter
    case couldNotCreatePixelBuffer
    case writerFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .gifTooLarge:
            "The GIF exceeds the 100 MB import limit."
        case .destinationAlreadyExists:
            "The GIF conversion destination already exists."
        case .unreadableGIF:
            "The selected GIF could not be read."
        case .unreadableFrame(let index):
            "GIF frame \(index + 1) could not be decoded."
        case .couldNotCreateWriter(let error):
            "The GIF video writer could not be created: \(error.localizedDescription)"
        case .couldNotConfigureWriter:
            "The GIF video writer could not be configured."
        case .couldNotCreatePixelBuffer:
            "A GIF video frame could not be created."
        case .writerFailed(let error):
            error?.localizedDescription ?? "The GIF video could not be written."
        }
    }
}
