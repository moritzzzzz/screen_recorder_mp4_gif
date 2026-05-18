import Foundation
import AVFoundation
import CoreMedia

class VideoWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?

    private var isWriting = false
    private var firstSampleTime: CMTime?
    private let outputURL: URL

    // Serialize all appends + session-start across the multiple sample-buffer sources
    // (video on SCStream's queue, system audio on SCStream's audio queue, mic on AVCapture queue)
    private let appendQueue = DispatchQueue(label: "com.screenrecorder.videowriter.append", qos: .userInteractive)

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func startWriting(
        width: Int,
        height: Int,
        includeSystemAudio: Bool = false,
        includeMicrophone: Bool = false
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw VideoWriterError.cannotAddInput }
        writer.add(videoInput)
        self.videoInput = videoInput

        // Optional audio inputs (separate tracks in the output MP4)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]

        if includeSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                self.systemAudioInput = input
            }
        }

        if includeMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                self.microphoneInput = input
            }
        }

        writer.startWriting()
        // Session start deferred until first sample arrives (from any source)

        self.assetWriter = writer
        self.isWriting = true
        self.firstSampleTime = nil
    }

    // MARK: - Append (one per source)

    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendQueue.async { [weak self] in
            self?.append(sampleBuffer, to: self?.videoInput)
        }
    }

    func appendSystemAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendQueue.async { [weak self] in
            self?.append(sampleBuffer, to: self?.systemAudioInput)
        }
    }

    func appendMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendQueue.async { [weak self] in
            self?.append(sampleBuffer, to: self?.microphoneInput)
        }
    }

    // Must be called on appendQueue
    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard isWriting,
              let writer = assetWriter,
              let input = input,
              writer.status == .writing
        else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstSampleTime == nil {
            firstSampleTime = timestamp
            writer.startSession(atSourceTime: timestamp)
        } else if let first = firstSampleTime, CMTimeCompare(timestamp, first) < 0 {
            // Sample from before session start — drop it
            return
        }

        guard input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    // MARK: - Finish

    func finishWriting() async throws -> URL {
        guard let writer = assetWriter else {
            throw VideoWriterError.notWriting
        }

        // Flip isWriting off + mark all inputs finished, on the same queue used by append.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            appendQueue.async { [weak self] in
                self?.isWriting = false
                self?.videoInput?.markAsFinished()
                self?.systemAudioInput?.markAsFinished()
                self?.microphoneInput?.markAsFinished()
                cont.resume()
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
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
        case .cannotAddInput: return "Cannot add input to asset writer."
        case .notWriting: return "Video writer is not currently writing."
        case .writingFailed: return "Video writing failed."
        }
    }
}
