import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

class CaptureEngine: NSObject, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var stream: SCStream?
    private var videoWriter: VideoWriter?
    private var micSession: AVCaptureSession?
    private let micQueue = DispatchQueue(label: "com.screenrecorder.mic", qos: .userInteractive)

    func startCapture(
        region: CapturedRegion,
        writer: VideoWriter,
        captureSystemAudio: Bool = false,
        captureMicrophone: Bool = false
    ) async throws {
        self.videoWriter = writer

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()

        // Video region (existing)
        let displayHeight = CGFloat(display.height)
        let sourceY = displayHeight - region.rect.origin.y - region.rect.height
        config.sourceRect = CGRect(
            x: region.rect.origin.x,
            y: sourceY,
            width: region.rect.width,
            height: region.rect.height
        )
        let pixelWidth = Int(region.rect.width * region.scaleFactor)
        let pixelHeight = Int(region.rect.height * region.scaleFactor)
        config.width = pixelWidth + (pixelWidth % 2)
        config.height = pixelHeight + (pixelHeight % 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        // System audio is captured by the same stream when enabled.
        config.capturesAudio = captureSystemAudio

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        }
        try await stream.startCapture()
        self.stream = stream

        // Microphone is captured via AVCaptureSession on all macOS versions
        if captureMicrophone {
            try setupMicrophoneCapture()
        }
    }

    private func setupMicrophoneCapture() throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            session.commitConfiguration()
            throw CaptureError.noMicrophone
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddMicrophoneInput
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: micQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddMicrophoneOutput
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
        self.micSession = session
    }

    func stopCapture() async throws {
        if let session = micSession {
            session.stopRunning()
            self.micSession = nil
        }
        if let stream = stream {
            try await stream.stopCapture()
            self.stream = nil
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            // Skip blank/idle frames
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusValue = attachments.first?[.status] as? Int,
                  statusValue == SCFrameStatus.complete.rawValue else {
                return
            }
            videoWriter?.appendVideoSampleBuffer(sampleBuffer)

        case .audio:
            videoWriter?.appendSystemAudioSampleBuffer(sampleBuffer)

        @unknown default:
            break
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        videoWriter?.appendMicrophoneSampleBuffer(sampleBuffer)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case permissionDenied
    case noMicrophone
    case cannotAddMicrophoneInput
    case cannotAddMicrophoneOutput

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the selected display."
        case .permissionDenied: return "Screen recording permission is required."
        case .noMicrophone: return "No microphone is available on this system."
        case .cannotAddMicrophoneInput: return "Could not add microphone input to capture session."
        case .cannotAddMicrophoneOutput: return "Could not add microphone output to capture session."
        }
    }
}
