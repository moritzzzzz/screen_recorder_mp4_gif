import Foundation
import AppKit
import AVFoundation

struct TimelineCut: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double   // in source media local time
    var endTime: Double

    var duration: Double { endTime - startTime }

    var durationText: String {
        String(format: "%.1fs", duration)
    }
}

enum TrackKind: String, Hashable {
    case video
    case audio
}

struct TrackRef: Hashable, Equatable {
    let assetID: UUID
    let kind: TrackKind
}

struct TimelineAsset: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    var sourceDuration: Double      // clip's playable duration (may be shorter than file)
    var sourceStartOffset: Double   // where in the underlying file this clip begins
    let hasAudio: Bool
    let renderSize: CGSize

    var thumbnails: [NSImage] = []
    var offset: Double = 0
    var videoCuts: [TimelineCut] = []
    var audioCuts: [TimelineCut] = []
    var videoEnabled: Bool = true
    var audioEnabled: Bool = true

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        sourceDuration: Double,
        hasAudio: Bool,
        renderSize: CGSize,
        sourceStartOffset: Double = 0
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.sourceDuration = sourceDuration
        self.hasAudio = hasAudio
        self.renderSize = renderSize
        self.sourceStartOffset = sourceStartOffset
    }

    func isEnabled(for kind: TrackKind) -> Bool {
        kind == .video ? videoEnabled : audioEnabled
    }

    var timelineEnd: Double { offset + sourceDuration }

    func cuts(for kind: TrackKind) -> [TimelineCut] {
        kind == .video ? videoCuts : audioCuts
    }

    /// Kept segments of the underlying media (in source-local time), after applying cuts.
    func keptSourceSegments(for kind: TrackKind) -> [(start: Double, end: Double)] {
        let cuts = self.cuts(for: kind).sorted { $0.startTime < $1.startTime }
        var segments: [(start: Double, end: Double)] = []
        var current: Double = 0
        for cut in cuts {
            if current < cut.startTime {
                segments.append((start: current, end: cut.startTime))
            }
            current = max(current, cut.endTime)
        }
        if current < sourceDuration {
            segments.append((start: current, end: sourceDuration))
        }
        return segments
    }

    static func == (lhs: TimelineAsset, rhs: TimelineAsset) -> Bool {
        lhs.id == rhs.id &&
        lhs.offset == rhs.offset &&
        lhs.videoCuts == rhs.videoCuts &&
        lhs.audioCuts == rhs.audioCuts &&
        lhs.thumbnails.count == rhs.thumbnails.count
    }

    // MARK: - Loading

    static func load(from url: URL, name: String? = nil) async throws -> TimelineAsset {
        let asset = AVURLAsset(url: url)
        let cmDuration = try await asset.load(.duration)
        let durationSec = CMTimeGetSeconds(cmDuration)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let renderSize: CGSize
        if let first = videoTracks.first {
            let naturalSize = try await first.load(.naturalSize)
            let transform = try await first.load(.preferredTransform)
            let transformed = naturalSize.applying(transform)
            renderSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        } else {
            renderSize = CGSize(width: 1280, height: 720)
        }

        return TimelineAsset(
            id: UUID(),
            url: url,
            name: name ?? url.lastPathComponent,
            sourceDuration: durationSec,
            hasAudio: !audioTracks.isEmpty,
            renderSize: renderSize
        )
    }

    // MARK: - Thumbnails

    static func generateThumbnails(
        for url: URL,
        startOffset: Double = 0,
        duration: Double,
        count: Int = 24
    ) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 120, height: 68)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)

        var images: [NSImage] = []
        for i in 0..<count {
            let seconds = startOffset + duration * Double(i) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                images.append(NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68)))
            } catch {
                let img = NSImage(size: NSSize(width: 120, height: 68))
                img.lockFocus()
                NSColor.darkGray.setFill()
                NSBezierPath.fill(NSRect(origin: .zero, size: img.size))
                img.unlockFocus()
                images.append(img)
            }
        }
        return images
    }
}
