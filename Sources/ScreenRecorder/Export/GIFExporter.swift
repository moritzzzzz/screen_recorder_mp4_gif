import Foundation
import AVFoundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

class GIFExporter {
    static func export(videoURL: URL, outputURL: URL, fps: Int = 10, maxWidth: Int = 640) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw GIFExportError.invalidDuration
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxWidth, height: 0)
        generator.appliesPreferredTrackTransform = true

        // Calculate frame times
        let frameCount = Int(durationSeconds * Double(fps))
        guard frameCount > 0 else {
            throw GIFExportError.noFrames
        }

        var times: [CMTime] = []
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) / Double(fps), preferredTimescale: 600)
            times.append(time)
        }

        // Create GIF destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw GIFExportError.cannotCreateDestination
        }

        // Set GIF-level properties (infinite loop)
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Per-frame properties
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 1.0 / Double(fps)
            ]
        ]

        // Extract frames and add to GIF
        for time in times {
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExportError.finalizationFailed
        }
    }
}

enum GIFExportError: LocalizedError {
    case invalidDuration
    case noFrames
    case cannotCreateDestination
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .invalidDuration: return "Video has no valid duration."
        case .noFrames: return "No frames could be generated."
        case .cannotCreateDestination: return "Could not create GIF file."
        case .finalizationFailed: return "Failed to finalize GIF."
        }
    }
}
