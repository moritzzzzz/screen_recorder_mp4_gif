import Foundation
import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

enum VideoSource: Equatable {
    case recorded
    case loaded(originalFilename: String)
}

@MainActor
class ScreenRecorderViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var selectedFormat: ExportFormat = .mp4
    @Published var selectedRegion: CapturedRegion?
    @Published var recordingDuration: TimeInterval = 0
    @Published var exportedFileURL: URL?
    @Published var editorModel: VideoEditorModel?
    @Published var videoSource: VideoSource = .recorded

    private let regionSelector = RegionSelectionController()
    private let captureEngine = CaptureEngine()
    private let exportManager = ExportManager()
    private var videoWriter: VideoWriter?
    private var durationTimer: Timer?
    private var tempVideoURL: URL?

    private static let normalSize = NSSize(width: 420, height: 572)
    private static let editorSize = NSSize(width: 820, height: 920)

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let tenths = Int((recordingDuration - Double(Int(recordingDuration))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    var regionDescription: String? {
        guard let region = selectedRegion else { return nil }
        let w = Int(region.rect.width)
        let h = Int(region.rect.height)
        return "\(w) x \(h) points"
    }

    // MARK: - Actions

    func openVideoFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Video to Edit"
        openPanel.message = "Choose an MP4, MPEG, or GIF file"
        openPanel.allowedContentTypes = [
            UTType.mpeg4Movie,
            UTType.movie,
            UTType.quickTimeMovie,
            UTType.mpeg,
            UTType.gif,
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        state = .processing

        Task {
            do {
                let videoURL: URL

                if url.pathExtension.lowercased() == "gif" {
                    videoURL = try await GIFConverter.convertGIFtoMP4(gifURL: url)
                } else {
                    let tempDir = FileManager.default.temporaryDirectory
                    let filename = "imported_\(Int(Date().timeIntervalSince1970)).mp4"
                    videoURL = tempDir.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: videoURL)
                    try FileManager.default.copyItem(at: url, to: videoURL)
                }

                let asset = AVURLAsset(url: videoURL)
                let cmDuration = try await asset.load(.duration)

                self.tempVideoURL = videoURL
                self.recordingDuration = CMTimeGetSeconds(cmDuration)
                self.videoSource = .loaded(originalFilename: url.lastPathComponent)
                self.exportedFileURL = nil
                self.state = .done(videoURL)
            } catch {
                state = .error("Failed to open video: \(error.localizedDescription)")
            }
        }
    }

    func selectRegion() {
        state = .selectingRegion
        Task {
            if let region = await regionSelector.beginSelection() {
                selectedRegion = region
                state = .idle
            } else {
                state = .idle
            }
        }
    }

    func startRecording() {
        guard let region = selectedRegion else { return }

        if !PermissionManager.hasScreenRecordingPermission() {
            _ = PermissionManager.requestScreenRecordingPermission()
            state = .error("Please grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording, then try again.")
            return
        }

        state = .countingDown(3)
        Task {
            for i in stride(from: 3, through: 1, by: -1) {
                state = .countingDown(i)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await beginCapture(region: region)
        }
    }

    func stopRecording() {
        Task {
            state = .processing

            do {
                try await captureEngine.stopCapture()
                stopDurationTimer()

                if let writer = videoWriter {
                    let url = try await writer.finishWriting()
                    tempVideoURL = url
                    videoSource = .recorded
                    state = .done(url)
                } else {
                    state = .error("No video writer available.")
                }
            } catch {
                state = .error("Failed to stop recording: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Editor

    func startEditing() {
        guard let url = tempVideoURL else { return }

        state = .editing(url)
        resizeWindow(to: Self.editorSize)

        Task {
            do {
                let editor = try await VideoEditorModel.create(videoURL: url)
                self.editorModel = editor
            } catch {
                state = .error("Failed to open editor: \(error.localizedDescription)")
                resizeWindow(to: Self.normalSize)
            }
        }
    }

    func finishEditing(editedURL: URL) {
        editorModel?.cleanup()
        editorModel = nil
        tempVideoURL = editedURL
        state = .done(editedURL)
        resizeWindow(to: Self.normalSize)
    }

    func cancelEditing() {
        editorModel?.cleanup()
        editorModel = nil
        if let url = tempVideoURL {
            state = .done(url)
        } else {
            state = .idle
        }
        resizeWindow(to: Self.normalSize)
    }

    // MARK: - Export

    func exportRecording() {
        guard let videoURL = tempVideoURL else { return }

        Task {
            do {
                if let savedURL = try await exportManager.export(videoAt: videoURL, as: selectedFormat) {
                    exportedFileURL = savedURL
                }
            } catch {
                state = .error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    func revealInFinder() {
        if let url = exportedFileURL {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } else if let url = tempVideoURL {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    func newRecording() {
        editorModel?.cleanup()
        editorModel = nil
        state = .idle
        selectedRegion = nil
        recordingDuration = 0
        exportedFileURL = nil
        tempVideoURL = nil
        videoWriter = nil
        videoSource = .recorded
    }

    func reset() {
        state = .idle
    }

    // MARK: - Private

    private func beginCapture(region: CapturedRegion) async {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "screenrecording_\(Int(Date().timeIntervalSince1970)).mp4"
        let url = tempDir.appendingPathComponent(filename)

        let pixelWidth = Int(region.rect.width * region.scaleFactor)
        let pixelHeight = Int(region.rect.height * region.scaleFactor)
        let width = pixelWidth + (pixelWidth % 2)
        let height = pixelHeight + (pixelHeight % 2)

        let writer = VideoWriter(outputURL: url)
        self.videoWriter = writer

        do {
            try writer.startWriting(width: width, height: height)
            try await captureEngine.startCapture(region: region, writer: writer)
            state = .recording
            startDurationTimer()
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func startDurationTimer() {
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func resizeWindow(to size: NSSize) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let oldFrame = window.frame
        let newFrame = NSRect(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.animator().setFrame(newFrame, display: true)
    }
}
