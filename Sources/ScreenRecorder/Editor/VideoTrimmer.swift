import AVFoundation

class VideoTrimmer {
    static func trim(
        videoURL: URL,
        keptSegments: [(start: Double, end: Double)],
        audioURL: URL? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimError.noVideoTrack
        }

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TrimError.cannotCreateTrack
        }

        let transform = try await videoTrack.load(.preferredTransform)
        compositionVideoTrack.preferredTransform = transform

        var insertTime = CMTime.zero
        for segment in keptSegments {
            let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
            let endTime = CMTime(seconds: segment.end, preferredTimescale: 600)
            let range = CMTimeRange(start: startTime, end: endTime)

            try compositionVideoTrack.insertTimeRange(range, of: videoTrack, at: insertTime)
            insertTime = insertTime + (endTime - startTime)
        }

        let totalVideoDuration = insertTime

        // Audio track (looped to fit video duration)
        var audioMix: AVAudioMix?
        if let audioURL = audioURL, totalVideoDuration > .zero {
            let audioAsset = AVURLAsset(url: audioURL)
            guard let audioSrcTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                throw TrimError.audioFileHasNoAudio
            }

            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw TrimError.cannotCreateTrack
            }

            let audioDuration = try await audioAsset.load(.duration)
            guard audioDuration > .zero else {
                throw TrimError.audioFileHasNoAudio
            }

            var audioInsertTime = CMTime.zero
            while audioInsertTime < totalVideoDuration {
                let remaining = totalVideoDuration - audioInsertTime
                let chunkDuration = CMTimeMinimum(audioDuration, remaining)
                let sourceRange = CMTimeRange(start: .zero, duration: chunkDuration)
                try compositionAudioTrack.insertTimeRange(sourceRange, of: audioSrcTrack, at: audioInsertTime)
                audioInsertTime = audioInsertTime + chunkDuration
            }

            // Fade in (1s at start) and fade out (1s at end), shrinking if the video is very short.
            let totalSeconds = CMTimeGetSeconds(totalVideoDuration)
            let fadeSeconds = min(1.0, totalSeconds / 2.0)
            if fadeSeconds > 0 {
                let fadeIn = CMTime(seconds: fadeSeconds, preferredTimescale: 600)
                let fadeOut = CMTime(seconds: fadeSeconds, preferredTimescale: 600)
                let params = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                params.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: 1,
                    timeRange: CMTimeRange(start: .zero, duration: fadeIn)
                )
                params.setVolumeRamp(
                    fromStartVolume: 1,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: totalVideoDuration - fadeOut, duration: fadeOut)
                )
                let mix = AVMutableAudioMix()
                mix.inputParameters = [params]
                audioMix = mix
            }
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
        exportSession.audioMix = audioMix

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
    case audioFileHasNoAudio

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Video has no video track."
        case .cannotCreateTrack: return "Could not create composition track."
        case .exportFailed: return "Video export failed."
        case .audioFileHasNoAudio: return "The selected audio file has no audio track."
        }
    }
}
