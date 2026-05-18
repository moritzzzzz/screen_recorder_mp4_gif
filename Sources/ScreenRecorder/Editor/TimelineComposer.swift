import AVFoundation
import CoreGraphics

private struct TrackEntry {
    let asset: TimelineAsset
    let videoTrack: AVMutableCompositionTrack
    let mediaVideoTrack: AVAssetTrack
    let timelineRanges: [CMTimeRange]
}

/// Builds an AVMutableComposition from a list of assets (with per-track cuts and offsets)
/// plus an optional music track. Higher-indexed video assets render on top (z-order).
class TimelineComposer {
    /// Build a composition + video composition + audio mix suitable for both preview and export.
    static func buildComposition(
        assets: [TimelineAsset],
        musicURL: URL? = nil
    ) async throws -> (
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        audioMix: AVMutableAudioMix?,
        renderSize: CGSize,
        timelineDuration: Double
    ) {
        let composition = AVMutableComposition()

        // Render size from the first video asset (primary)
        let primarySize = assets.first?.renderSize ?? CGSize(width: 1280, height: 720)
        let evenWidth = max(2, Int(primarySize.width) + (Int(primarySize.width) % 2))
        let evenHeight = max(2, Int(primarySize.height) + (Int(primarySize.height) % 2))
        let renderSize = CGSize(width: evenWidth, height: evenHeight)

        // Track timeline-end across all assets to find total duration
        var maxTimelineEnd: Double = 0

        var trackEntries: [TrackEntry] = []

        // For audio mix params
        var audioInputParams: [AVMutableAudioMixInputParameters] = []

        for asset in assets {
            let urlAsset = AVURLAsset(url: asset.url)

            // Always update maxTimelineEnd based on asset's overall span (even if disabled)
            // so disabled tracks still affect timeline duration.
            maxTimelineEnd = max(maxTimelineEnd, asset.offset + asset.sourceDuration)

            // VIDEO sub-track
            if asset.videoEnabled,
               let mediaVideoTrack = try await urlAsset.loadTracks(withMediaType: .video).first,
               let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                compVideoTrack.preferredTransform = try await mediaVideoTrack.load(.preferredTransform)

                let videoSegments = asset.keptSourceSegments(for: .video)
                var timelineRanges: [CMTimeRange] = []
                for seg in videoSegments {
                    let srcStart = CMTime(seconds: seg.start + asset.sourceStartOffset, preferredTimescale: 600)
                    let srcEnd = CMTime(seconds: seg.end + asset.sourceStartOffset, preferredTimescale: 600)
                    let srcRange = CMTimeRange(start: srcStart, end: srcEnd)
                    let dest = CMTime(seconds: asset.offset + seg.start, preferredTimescale: 600)
                    try compVideoTrack.insertTimeRange(srcRange, of: mediaVideoTrack, at: dest)
                    let timelineRange = CMTimeRange(start: dest, duration: srcEnd - srcStart)
                    timelineRanges.append(timelineRange)
                    let endSec = CMTimeGetSeconds(dest) + CMTimeGetSeconds(srcEnd - srcStart)
                    maxTimelineEnd = max(maxTimelineEnd, endSec)
                }

                trackEntries.append(TrackEntry(
                    asset: asset,
                    videoTrack: compVideoTrack,
                    mediaVideoTrack: mediaVideoTrack,
                    timelineRanges: timelineRanges
                ))
            }

            // AUDIO sub-track
            if asset.hasAudio,
               asset.audioEnabled,
               let mediaAudio = try await urlAsset.loadTracks(withMediaType: .audio).first,
               let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let audioSegments = asset.keptSourceSegments(for: .audio)
                for seg in audioSegments {
                    let srcStart = CMTime(seconds: seg.start + asset.sourceStartOffset, preferredTimescale: 600)
                    let srcEnd = CMTime(seconds: seg.end + asset.sourceStartOffset, preferredTimescale: 600)
                    let srcRange = CMTimeRange(start: srcStart, end: srcEnd)
                    let dest = CMTime(seconds: asset.offset + seg.start, preferredTimescale: 600)
                    try compAudioTrack.insertTimeRange(srcRange, of: mediaAudio, at: dest)
                    let endSec = CMTimeGetSeconds(dest) + (seg.end - seg.start)
                    maxTimelineEnd = max(maxTimelineEnd, endSec)
                }
                let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
                audioInputParams.append(params)
            }
        }

        let timelineDuration = maxTimelineEnd

        // Music track (looped to fit total timeline)
        if let musicURL, timelineDuration > 0 {
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicSrc = try await musicAsset.loadTracks(withMediaType: .audio).first,
               let compMusic = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let musicDuration = try await musicAsset.load(.duration)
                if musicDuration > .zero {
                    let totalCM = CMTime(seconds: timelineDuration, preferredTimescale: 600)
                    var t = CMTime.zero
                    while t < totalCM {
                        let remaining = totalCM - t
                        let chunk = CMTimeMinimum(musicDuration, remaining)
                        let srcRange = CMTimeRange(start: .zero, duration: chunk)
                        try compMusic.insertTimeRange(srcRange, of: musicSrc, at: t)
                        t = t + chunk
                    }
                    let params = AVMutableAudioMixInputParameters(track: compMusic)
                    audioInputParams.append(params)
                }
            }
        }

        // Audio mix with fade in / out applied to ALL audio tracks
        var audioMix: AVMutableAudioMix?
        if !audioInputParams.isEmpty, timelineDuration > 0 {
            let fadeSeconds = min(1.0, timelineDuration / 2.0)
            if fadeSeconds > 0 {
                let fadeIn = CMTime(seconds: fadeSeconds, preferredTimescale: 600)
                let fadeOut = CMTime(seconds: fadeSeconds, preferredTimescale: 600)
                let totalCM = CMTime(seconds: timelineDuration, preferredTimescale: 600)
                for p in audioInputParams {
                    p.setVolumeRamp(
                        fromStartVolume: 0, toEndVolume: 1,
                        timeRange: CMTimeRange(start: .zero, duration: fadeIn)
                    )
                    p.setVolumeRamp(
                        fromStartVolume: 1, toEndVolume: 0,
                        timeRange: CMTimeRange(start: totalCM - fadeOut, duration: fadeOut)
                    )
                }
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioInputParams
            audioMix = mix
        }

        // Video composition with z-ordering: later-added on top.
        // We build per-time-range instructions so opacity flips between tracks correctly.
        let videoComposition = buildVideoComposition(
            entries: trackEntries,
            renderSize: renderSize,
            timelineDuration: timelineDuration
        )

        return (composition, videoComposition, audioMix, renderSize, timelineDuration)
    }

    /// Construct the video composition.
    ///
    /// Strategy: ONE instruction covering the entire timeline, with one layer instruction per
    /// asset's video track. Each layer is permanently at opacity 1 — the track simply has no
    /// media outside its own time range, so it contributes nothing during those moments. The
    /// layer instructions are added in REVERSE order so later-added assets end up on top
    /// (first in `layerInstructions` is topmost). Explicit `setTransform(...)` keeps each
    /// track's preferred transform applied — without it, AVPlayer falls back to identity and
    /// the preview can render off-screen or blank for multi-track compositions.
    private static func buildVideoComposition(
        entries: [TrackEntry],
        renderSize: CGSize,
        timelineDuration: Double
    ) -> AVMutableVideoComposition? {
        guard timelineDuration > 0, !entries.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let totalCM = CMTime(seconds: timelineDuration, preferredTimescale: 600)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: totalCM)
        instr.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for entry in entries.reversed() {
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: entry.videoTrack)
            li.setOpacity(1.0, at: .zero)
            li.setTransform(entry.videoTrack.preferredTransform, at: .zero)
            layerInstructions.append(li)
        }
        instr.layerInstructions = layerInstructions
        videoComposition.instructions = [instr]

        return videoComposition
    }

    // MARK: - Export

    /// Exports the timeline to a new MP4 file using AVAssetExportSession.
    static func exportTimeline(
        assets: [TimelineAsset],
        musicURL: URL? = nil
    ) async throws -> URL {
        let (composition, videoComposition, audioMix, _, _) = try await buildComposition(
            assets: assets,
            musicURL: musicURL
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw TimelineComposerError.exportFailed }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.audioMix = audioMix

        await session.export()
        guard session.status == .completed else {
            throw session.error ?? TimelineComposerError.exportFailed
        }
        return outputURL
    }
}

enum TimelineComposerError: LocalizedError {
    case exportFailed
    case noAssets

    var errorDescription: String? {
        switch self {
        case .exportFailed: return "Timeline export failed."
        case .noAssets: return "No assets in timeline."
        }
    }
}
