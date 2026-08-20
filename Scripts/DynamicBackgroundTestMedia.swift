@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DynamicBackgroundTestMedia {
    static func makePNG(
        at url: URL,
        width: Int = 32,
        height: Int = 24
    ) throws {
        let image = try makeSolidImage(
            red: 1,
            green: 0,
            blue: 0,
            width: width,
            height: height
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestMediaError.unableToCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestMediaError.unableToFinalizeImage
        }
    }

    static func makeTwoFrameGIF(at url: URL) throws {
        try makeTwoFrameGIF(at: url, width: 32, height: 24)
    }

    static func makeOversizedTwoFrameGIF(at url: URL) throws {
        try makeTwoFrameGIF(at: url, width: 2_000, height: 1_000)
    }

    static func makeCancellationGIF(at url: URL) throws {
        let red = try makeSolidImage(red: 1, green: 0, blue: 0, width: 640, height: 480)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1, width: 640, height: 480)
        try writeGIF(
            at: url,
            frames: (0..<120).map { $0.isMultiple(of: 2) ? red : blue },
            delays: Array(repeating: 0.02, count: 120)
        )
    }

    static func makeTransparentGIFWithLogicalBackground(at url: URL) throws {
        try writeTransparentGIF(at: url, includesGlobalColorTable: true)
    }

    static func makeTransparentGIFWithoutLogicalBackground(at url: URL) throws {
        try writeTransparentGIF(at: url, includesGlobalColorTable: false)
    }

    static func extendFile(at url: URL, toByteCount byteCount: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(byteCount))
    }

    static func makeSilentH264Video(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = 32
        let height = 24
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
        )
        guard writer.canAdd(input) else {
            throw TestMediaError.unableToConfigureVideoWriter
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw TestMediaError.videoWriterFailed(writer.error?.localizedDescription)
        }
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw TestMediaError.unableToCreatePixelBuffer
        }
        let red = try makePixelBuffer(
            pool: pool,
            width: width,
            height: height,
            red: 1,
            green: 0,
            blue: 0
        )
        let blue = try makePixelBuffer(
            pool: pool,
            width: width,
            height: height,
            red: 0,
            green: 0,
            blue: 1
        )
        guard adaptor.append(red, withPresentationTime: .zero),
              adaptor.append(
                blue,
                withPresentationTime: CMTime(seconds: 0.5, preferredTimescale: 600)
              ) else {
            throw TestMediaError.videoWriterFailed(writer.error?.localizedDescription)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))

        let writerBox = TestMediaUncheckedSendable(writer)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                let writer = writerBox.value
                guard writer.status == .completed else {
                    continuation.resume(
                        throwing: TestMediaError.videoWriterFailed(
                            writer.error?.localizedDescription
                        )
                    )
                    return
                }
                continuation.resume()
            }
        }
    }

    static func makeAudioVideoMOV(at url: URL, workingDirectory: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        let silentVideoURL = workingDirectory.appendingPathComponent("silent-source.mp4")
        let audioURL = workingDirectory.appendingPathComponent("tone.caf")
        try await makeSilentH264Video(at: silentVideoURL)
        try makePCMAudio(at: audioURL)

        let videoAsset = AVURLAsset(url: silentVideoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(
            withMediaType: .video
        ).first,
              let sourceAudioTrack = try await audioAsset.loadTracks(
                withMediaType: .audio
              ).first else {
            throw TestMediaError.unableToBuildComposition
        }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
              let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw TestMediaError.unableToBuildComposition
        }
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        try audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TestMediaError.unableToCreateExporter
        }
        exporter.shouldOptimizeForNetworkUse = false
        if #available(macOS 15.0, *) {
            try await exporter.export(to: url, as: .mov)
        } else {
            exporter.outputURL = url
            exporter.outputFileType = .mov
            await exporter.export()
            guard exporter.status == .completed else {
                throw TestMediaError.exportFailed(exporter.error?.localizedDescription)
            }
        }
    }

    private static func makeTwoFrameGIF(at url: URL, width: Int, height: Int) throws {
        let red = try makeSolidImage(red: 1, green: 0, blue: 0, width: width, height: height)
        let blue = try makeSolidImage(red: 0, green: 0, blue: 1, width: width, height: height)
        try writeGIF(at: url, frames: [red, blue], delays: [0.10, 0.25])
    }

    private static func writeGIF(at url: URL, frames: [CGImage], delays: [Double]) throws {
        guard frames.count == delays.count else {
            throw TestMediaError.frameDelayCountMismatch
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw TestMediaError.unableToCreateDestination
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0,
                ],
            ] as CFDictionary
        )

        for (image, delay) in zip(frames, delays) {
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                    kCGImagePropertyGIFDelayTime: delay,
                ],
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw TestMediaError.unableToFinalizeGIF
        }
    }

    private static func makeSolidImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw TestMediaError.unableToCreateImage
        }

        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestMediaError.unableToCreateImage
        }
        return image
    }

    private static func makePixelBuffer(
        pool: CVPixelBufferPool,
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else {
            throw TestMediaError.unableToCreatePixelBuffer
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw TestMediaError.unableToCreateImage
        }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func makePCMAudio(at url: URL) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleRate)
              ),
              let samples = buffer.int16ChannelData?[0] else {
            throw TestMediaError.unableToCreateAudio
        }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            let phase = Double(index) / sampleRate * 440 * 2 * Double.pi
            samples[index] = Int16(sin(phase) * Double(Int16.max) * 0.1)
        }
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        try audioFile.write(from: buffer)
    }

    private static func writeTransparentGIF(
        at url: URL,
        includesGlobalColorTable: Bool
    ) throws {
        let width = 32
        let height = 24
        var data = Data("GIF89a".utf8)
        data.appendLittleEndian(UInt16(width))
        data.appendLittleEndian(UInt16(height))
        data.append(includesGlobalColorTable ? 0x80 : 0x00)
        data.append(0)
        data.append(0)

        let palette: [UInt8] = [
            includesGlobalColorTable ? 0 : 255,
            includesGlobalColorTable ? 255 : 0,
            0,
            255, 0, 0,
        ]
        if includesGlobalColorTable {
            data.append(contentsOf: palette)
        }

        data.append(contentsOf: [
            0x21, 0xF9, 0x04,
            0x01,
            0x0A, 0x00,
            0x00,
            0x00,
            0x2C,
        ])
        data.appendLittleEndian(0)
        data.appendLittleEndian(0)
        data.appendLittleEndian(UInt16(width))
        data.appendLittleEndian(UInt16(height))
        data.append(includesGlobalColorTable ? 0x00 : 0x80)
        if !includesGlobalColorTable {
            data.append(contentsOf: palette)
        }

        let pixels = (0..<height).flatMap { _ in
            (0..<width).map { $0 < width / 2 ? UInt8(0) : UInt8(1) }
        }
        let compressed = clearSeparatedLZWData(for: pixels)
        data.append(2)
        var offset = 0
        while offset < compressed.count {
            let count = min(255, compressed.count - offset)
            data.append(UInt8(count))
            data.append(contentsOf: compressed[offset..<(offset + count)])
            offset += count
        }
        data.append(0)
        data.append(0x3B)
        try data.write(to: url)
    }

    private static func clearSeparatedLZWData(for pixels: [UInt8]) -> [UInt8] {
        let clearCode = 4
        let endCode = 5
        var codes = pixels.flatMap { [clearCode, Int($0)] }
        codes.append(endCode)

        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        var bitIndex = 0
        for code in codes {
            for codeBit in 0..<3 {
                if code & (1 << codeBit) != 0 {
                    byte |= 1 << bitIndex
                }
                bitIndex += 1
                if bitIndex == 8 {
                    bytes.append(byte)
                    byte = 0
                    bitIndex = 0
                }
            }
        }
        if bitIndex > 0 {
            bytes.append(byte)
        }
        return bytes
    }
}

private enum TestMediaError: Error {
    case unableToCreateDestination
    case unableToFinalizeGIF
    case unableToFinalizeImage
    case unableToCreateImage
    case frameDelayCountMismatch
    case unableToConfigureVideoWriter
    case unableToCreatePixelBuffer
    case videoWriterFailed(String?)
    case unableToCreateAudio
    case unableToBuildComposition
    case unableToCreateExporter
    case exportFailed(String?)
}

private final class TestMediaUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}
