import AVFoundation
import CoreVideo
import CoreGraphics
import ImageIO

class GIFConverter {
    static func convertGIFtoMP4(gifURL: URL) async throws -> URL {
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            throw GIFConverterError.cannotReadGIF
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw GIFConverterError.noFrames
        }

        guard let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GIFConverterError.cannotReadFrame
        }

        let width = firstFrame.width + (firstFrame.width % 2)
        let height = firstFrame.height + (firstFrame.height % 2)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif_imported_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(input) else {
            throw GIFConverterError.cannotAddInput
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw GIFConverterError.cannotStartWriting
        }
        writer.startSession(atSourceTime: .zero)

        var currentTime = CMTime.zero

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            // Read this frame's delay from the GIF metadata
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifProps = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let rawDelay: Double = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime as String] as? Double)
                ?? 0.1
            // Many GIFs encode "0" meaning "as fast as possible" — browsers treat as ~0.1s
            let delay = rawDelay > 0.011 ? rawDelay : 0.1

            // Wait for the writer to be ready
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }

            guard let pixelBuffer = createPixelBuffer(from: cgImage, width: width, height: height, adaptor: adaptor) else {
                continue
            }

            adaptor.append(pixelBuffer, withPresentationTime: currentTime)
            currentTime = currentTime + CMTime(seconds: delay, preferredTimescale: 600)
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? GIFConverterError.writingFailed
        }

        return outputURL
    }

    private static func createPixelBuffer(
        from cgImage: CGImage,
        width: Int,
        height: Int,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        // Solid black background (handles GIFs with transparency or sub-frame updates)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Center the frame in case its dimensions don't exactly match the even-padded canvas
        let drawW = cgImage.width
        let drawH = cgImage.height
        let xOffset = (width - drawW) / 2
        let yOffset = (height - drawH) / 2
        context.draw(cgImage, in: CGRect(x: xOffset, y: yOffset, width: drawW, height: drawH))

        return buffer
    }
}

enum GIFConverterError: LocalizedError {
    case cannotReadGIF
    case noFrames
    case cannotReadFrame
    case cannotAddInput
    case cannotStartWriting
    case writingFailed

    var errorDescription: String? {
        switch self {
        case .cannotReadGIF: return "Could not read GIF file."
        case .noFrames: return "GIF contains no frames."
        case .cannotReadFrame: return "Could not read GIF frame."
        case .cannotAddInput: return "Cannot add video input to writer."
        case .cannotStartWriting: return "Cannot start writing video file."
        case .writingFailed: return "Failed while writing converted video."
        }
    }
}
