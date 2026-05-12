import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

class CaptureEngine: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var videoWriter: VideoWriter?

    func startCapture(region: CapturedRegion, writer: VideoWriter) async throws {
        self.videoWriter = writer

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()

        // Convert from NSScreen coordinates (bottom-left origin) to display coordinates (top-left origin)
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
        // Ensure dimensions are even (required for H.264)
        config.width = pixelWidth + (pixelWidth % 2)
        config.height = pixelHeight + (pixelHeight % 2)

        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream
    }

    func stopCapture() async throws {
        guard let stream = stream else { return }
        try await stream.stopCapture()
        self.stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        // Check for display status — skip blank/idle frames
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              statusValue == SCFrameStatus.complete.rawValue else {
            return
        }

        videoWriter?.appendSampleBuffer(sampleBuffer)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the selected display."
        case .permissionDenied: return "Screen recording permission is required."
        }
    }
}
