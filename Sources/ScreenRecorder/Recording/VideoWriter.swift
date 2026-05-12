import Foundation
import AVFoundation
import CoreMedia

class VideoWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isWriting = false
    private var firstSampleTime: CMTime?
    private let outputURL: URL

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func startWriting(width: Int, height: Int) throws {
        // Remove existing file if present
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
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw VideoWriterError.cannotAddInput
        }
        writer.add(input)

        writer.startWriting()
        // Session start time will be set when first buffer arrives

        self.assetWriter = writer
        self.videoInput = input
        self.isWriting = true
        self.firstSampleTime = nil
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting,
              let writer = assetWriter,
              let input = videoInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstSampleTime == nil {
            firstSampleTime = timestamp
            writer.startSession(atSourceTime: timestamp)
        }

        input.append(sampleBuffer)
    }

    func finishWriting() async throws -> URL {
        guard let writer = assetWriter, let input = videoInput else {
            throw VideoWriterError.notWriting
        }

        isWriting = false
        input.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed {
            throw writer.error ?? VideoWriterError.writingFailed
        }

        return outputURL
    }
}

enum VideoWriterError: LocalizedError {
    case cannotAddInput
    case notWriting
    case writingFailed

    var errorDescription: String? {
        switch self {
        case .cannotAddInput: return "Cannot add video input to asset writer."
        case .notWriting: return "Video writer is not currently writing."
        case .writingFailed: return "Video writing failed."
        }
    }
}
