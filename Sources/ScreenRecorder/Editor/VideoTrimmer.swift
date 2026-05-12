import AVFoundation

class VideoTrimmer {
    static func trim(videoURL: URL, keptSegments: [(start: Double, end: Double)]) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimError.noVideoTrack
        }

        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TrimError.cannotCreateTrack
        }

        // Copy the transform so orientation is preserved
        let transform = try await videoTrack.load(.preferredTransform)
        compositionTrack.preferredTransform = transform

        var insertTime = CMTime.zero
        for segment in keptSegments {
            let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
            let endTime = CMTime(seconds: segment.end, preferredTimescale: 600)
            let range = CMTimeRange(start: startTime, end: endTime)

            try compositionTrack.insertTimeRange(range, of: videoTrack, at: insertTime)
            insertTime = insertTime + (endTime - startTime)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? TrimError.exportFailed
        }

        return outputURL
    }
}

enum TrimError: LocalizedError {
    case noVideoTrack
    case cannotCreateTrack
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Video has no video track."
        case .cannotCreateTrack: return "Could not create composition track."
        case .exportFailed: return "Video export failed."
        }
    }
}
