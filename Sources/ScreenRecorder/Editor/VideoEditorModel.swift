import Foundation
import AVFoundation
import AppKit
import Combine

struct CutRange: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double
    var endTime: Double

    var durationText: String {
        let dur = endTime - startTime
        return String(format: "%.1fs", dur)
    }
}

@MainActor
class VideoEditorModel: ObservableObject {
    let videoURL: URL
    let duration: Double
    let player: AVPlayer

    @Published var thumbnails: [NSImage] = []
    @Published var cutRanges: [CutRange] = []
    @Published var selectionStart: Double?
    @Published var selectionEnd: Double?
    @Published var playheadTime: Double = 0
    @Published var isPlaying: Bool = false
    @Published var isProcessing: Bool = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(videoURL: URL, duration: Double) {
        self.videoURL = videoURL
        self.duration = duration
        self.player = AVPlayer(url: videoURL)

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isPlaying {
                    self.playheadTime = min(CMTimeGetSeconds(time), self.duration)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = false
                self.playheadTime = self.duration
            }
        }
    }

    static func create(videoURL: URL) async throws -> VideoEditorModel {
        let asset = AVURLAsset(url: videoURL)
        let cmDuration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(cmDuration)
        return VideoEditorModel(videoURL: videoURL, duration: seconds)
    }

    func cleanup() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    // MARK: - Thumbnails

    func generateThumbnails(count: Int = 30) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        var images: [NSImage] = []
        for i in 0..<count {
            let seconds = duration * Double(i) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 90))
                images.append(nsImage)
            } catch {
                // Use a gray placeholder for failed frames
                let img = NSImage(size: NSSize(width: 160, height: 90))
                img.lockFocus()
                NSColor.darkGray.setFill()
                NSBezierPath.fill(NSRect(origin: .zero, size: img.size))
                img.unlockFocus()
                images.append(img)
            }
        }

        self.thumbnails = images
    }

    // MARK: - Playback

    func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        playheadTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playheadTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    // MARK: - Selection

    func markStart() {
        selectionStart = playheadTime
        if let end = selectionEnd, end <= playheadTime {
            selectionEnd = nil
        }
    }

    func markEnd() {
        selectionEnd = playheadTime
        if let start = selectionStart, start >= playheadTime {
            selectionStart = nil
        }
    }

    func setSelection(start: Double, end: Double) {
        selectionStart = min(start, end)
        selectionEnd = max(start, end)
    }

    func clearSelection() {
        selectionStart = nil
        selectionEnd = nil
    }

    var hasValidSelection: Bool {
        guard let s = selectionStart, let e = selectionEnd else { return false }
        return e - s > 0.05
    }

    // MARK: - Cuts

    func deleteSelection() {
        guard let start = selectionStart, let end = selectionEnd, start < end else { return }

        var merged = CutRange(startTime: start, endTime: end)
        var remaining: [CutRange] = []

        for existing in cutRanges {
            if existing.startTime <= merged.endTime && existing.endTime >= merged.startTime {
                merged = CutRange(
                    startTime: min(merged.startTime, existing.startTime),
                    endTime: max(merged.endTime, existing.endTime)
                )
            } else {
                remaining.append(existing)
            }
        }

        remaining.append(merged)
        remaining.sort { $0.startTime < $1.startTime }
        cutRanges = remaining

        selectionStart = nil
        selectionEnd = nil
    }

    func removeCut(_ cut: CutRange) {
        cutRanges.removeAll { $0.id == cut.id }
    }

    func removeAllCuts() {
        cutRanges.removeAll()
    }

    // MARK: - Export

    var keptSegments: [(start: Double, end: Double)] {
        var segments: [(start: Double, end: Double)] = []
        var current: Double = 0
        let sorted = cutRanges.sorted { $0.startTime < $1.startTime }

        for cut in sorted {
            if current < cut.startTime {
                segments.append((start: current, end: cut.startTime))
            }
            current = cut.endTime
        }

        if current < duration {
            segments.append((start: current, end: duration))
        }

        return segments
    }

    var trimmedDuration: Double {
        keptSegments.reduce(0) { $0 + ($1.end - $1.start) }
    }

    var removedDuration: Double {
        cutRanges.reduce(0) { $0 + ($1.endTime - $1.startTime) }
    }

    func exportTrimmedVideo() async throws -> URL {
        isProcessing = true
        defer { isProcessing = false }

        if cutRanges.isEmpty {
            return videoURL
        }

        return try await VideoTrimmer.trim(videoURL: videoURL, keptSegments: keptSegments)
    }

    // MARK: - Helpers

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }
}
