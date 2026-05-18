import Foundation
import AVFoundation
import AppKit
import Combine
import UniformTypeIdentifiers

// Kept around for backward compatibility — used by audio fade logic in VideoTrimmer.
// The new multi-track timeline uses TimelineCut.
struct CutRange: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double
    var endTime: Double

    var durationText: String {
        String(format: "%.1fs", endTime - startTime)
    }
}

@MainActor
class VideoEditorModel: ObservableObject {
    // MARK: - Timeline state

    @Published var assets: [TimelineAsset] = []
    @Published var selectedTrack: TrackRef?
    @Published var selectionStart: Double?   // timeline time
    @Published var selectionEnd: Double?     // timeline time
    @Published var playheadTime: Double = 0  // timeline time
    @Published var isPlaying: Bool = false
    @Published var isProcessing: Bool = false
    @Published var processingMessage: String = "Processing\u{2026}"
    @Published var isAddingAsset: Bool = false

    // MARK: - Audio music (unchanged from single-track version)

    @Published var audioChoice: AudioTrackChoice = .none
    @Published var isPreparingAudio: Bool = false
    @Published var isPreviewingAudio: Bool = false
    @Published var audioError: String?

    private var preparedMusicURL: URL?
    private var previewPlayer: AVAudioPlayer?

    // MARK: - Player

    let player: AVPlayer
    private var compositionDirty: Bool = true
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // MARK: - Initial primary asset

    let primaryURL: URL
    let initialPrimaryDuration: Double

    init(videoURL: URL, duration: Double) {
        self.primaryURL = videoURL
        self.initialPrimaryDuration = duration
        self.player = AVPlayer()

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isPlaying {
                    self.playheadTime = min(CMTimeGetSeconds(time), self.totalDuration)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = false
                self.playheadTime = self.totalDuration
            }
        }
    }

    static func create(videoURL: URL) async throws -> VideoEditorModel {
        let asset = AVURLAsset(url: videoURL)
        let cmDuration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(cmDuration)
        let model = VideoEditorModel(videoURL: videoURL, duration: seconds)
        // Load primary asset
        try await model.addInitialPrimaryAsset(url: videoURL)
        return model
    }

    private func addInitialPrimaryAsset(url: URL) async throws {
        let asset = try await TimelineAsset.load(from: url, name: "Primary")
        assets.append(asset)
        let dur = asset.sourceDuration
        Task { [id = asset.id] in
            let thumbs = await TimelineAsset.generateThumbnails(for: url, duration: dur, count: 24)
            if let idx = self.assets.firstIndex(where: { $0.id == id }) {
                self.assets[idx].thumbnails = thumbs
            }
        }
        compositionDirty = true
    }

    func cleanup() {
        player.pause()
        stopPreview()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    // MARK: - Computed timeline properties

    var totalDuration: Double {
        let maxEnd = assets.map { $0.timelineEnd }.max() ?? 0
        // Use initial primary duration as a floor before any asset finishes loading
        return max(maxEnd, 0)
    }

    var duration: Double { totalDuration }

    var hasValidSelection: Bool {
        guard let s = selectionStart, let e = selectionEnd else { return false }
        return (e - s) > 0.05 && selectedTrack != nil
    }

    // MARK: - Adding / removing tracks

    func addVideoFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Add Video to Timeline"
        panel.allowedContentTypes = [.mpeg4Movie, .movie, .quickTimeMovie, .mpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await addVideo(from: url)
        }
    }

    func addVideo(from sourceURL: URL) async {
        isAddingAsset = true
        defer { isAddingAsset = false }

        // GIF → MP4 conversion first
        let workingURL: URL
        do {
            if sourceURL.pathExtension.lowercased() == "gif" {
                workingURL = try await GIFConverter.convertGIFtoMP4(gifURL: sourceURL)
            } else {
                let tempDir = FileManager.default.temporaryDirectory
                let dest = tempDir.appendingPathComponent("import_\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
                try FileManager.default.copyItem(at: sourceURL, to: dest)
                workingURL = dest
            }
        } catch {
            audioError = "Could not import video: \(error.localizedDescription)"
            return
        }

        do {
            var asset = try await TimelineAsset.load(from: workingURL, name: sourceURL.lastPathComponent)
            // Place new asset at the end of the current timeline (sequential by default)
            asset.offset = totalDuration
            let assetID = asset.id
            let assetURL = asset.url
            let assetDur = asset.sourceDuration
            assets.append(asset)
            compositionDirty = true

            // Thumbnails in background
            Task {
                let thumbs = await TimelineAsset.generateThumbnails(for: assetURL, duration: assetDur, count: 24)
                if let idx = self.assets.firstIndex(where: { $0.id == assetID }) {
                    self.assets[idx].thumbnails = thumbs
                }
            }
        } catch {
            audioError = "Could not load video: \(error.localizedDescription)"
        }
    }

    func toggleTrackEnabled(assetID: UUID, kind: TrackKind) {
        guard let idx = assets.firstIndex(where: { $0.id == assetID }) else { return }
        switch kind {
        case .video:
            assets[idx].videoEnabled.toggle()
        case .audio:
            assets[idx].audioEnabled.toggle()
        }
        compositionDirty = true
    }

    func removeAsset(id: UUID) {
        assets.removeAll { $0.id == id }
        if let sel = selectedTrack, sel.assetID == id {
            selectedTrack = nil
            selectionStart = nil
            selectionEnd = nil
        }
        compositionDirty = true
    }

    func setOffset(forAssetID id: UUID, offset: Double, snapTolerance: Double = 0) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        var newOffset = max(0, offset)

        if snapTolerance > 0 {
            let points = snapPoints(excludingAssetID: id)
            let dur = assets[idx].sourceDuration

            // Try snapping the left edge
            var snapped = false
            for sp in points where abs(newOffset - sp) <= snapTolerance {
                newOffset = sp
                snapped = true
                break
            }
            // If left edge didn't snap, try the right edge (asset end aligns with point)
            if !snapped {
                for sp in points where abs((newOffset + dur) - sp) <= snapTolerance {
                    newOffset = max(0, sp - dur)
                    break
                }
            }
        }

        assets[idx].offset = newOffset
        compositionDirty = true
    }

    /// Timeline-time positions that other tracks (and their cuts) suggest as alignment anchors.
    func snapPoints(excludingAssetID: UUID?) -> [Double] {
        var points: Set<Double> = [0]
        for asset in assets {
            if asset.id == excludingAssetID { continue }
            points.insert(asset.offset)
            points.insert(asset.offset + asset.sourceDuration)
            for cut in asset.videoCuts {
                points.insert(asset.offset + cut.startTime)
                points.insert(asset.offset + cut.endTime)
            }
            for cut in asset.audioCuts {
                points.insert(asset.offset + cut.startTime)
                points.insert(asset.offset + cut.endTime)
            }
        }
        return Array(points).sorted()
    }

    /// Split the currently selected track at the playhead, creating two independent assets
    /// that reference the same underlying file. Returns true if a split occurred.
    @discardableResult
    func splitSelectedTrackAtPlayhead() -> Bool {
        guard let ref = selectedTrack,
              let idx = assets.firstIndex(where: { $0.id == ref.assetID })
        else { return false }

        let original = assets[idx]
        let localSplit = playheadTime - original.offset

        // Must be strictly inside the clip
        let minMargin = 0.05
        if localSplit <= minMargin || localSplit >= original.sourceDuration - minMargin {
            return false
        }

        // First half — keep same id, trim the duration; remap cuts.
        var first = original
        first.sourceDuration = localSplit
        first.videoCuts = original.videoCuts.compactMap { cut in
            if cut.endTime <= localSplit { return cut }
            if cut.startTime >= localSplit { return nil }
            return TimelineCut(startTime: cut.startTime, endTime: localSplit)
        }
        first.audioCuts = original.audioCuts.compactMap { cut in
            if cut.endTime <= localSplit { return cut }
            if cut.startTime >= localSplit { return nil }
            return TimelineCut(startTime: cut.startTime, endTime: localSplit)
        }
        first.thumbnails = []

        // Second half — new id, points further into the source file via sourceStartOffset.
        var second = TimelineAsset(
            id: UUID(),
            url: original.url,
            name: original.name,
            sourceDuration: original.sourceDuration - localSplit,
            hasAudio: original.hasAudio,
            renderSize: original.renderSize,
            sourceStartOffset: original.sourceStartOffset + localSplit
        )
        second.offset = original.offset + localSplit
        second.videoCuts = original.videoCuts.compactMap { cut in
            if cut.startTime >= localSplit {
                return TimelineCut(startTime: cut.startTime - localSplit, endTime: cut.endTime - localSplit)
            }
            if cut.endTime <= localSplit { return nil }
            return TimelineCut(startTime: 0, endTime: cut.endTime - localSplit)
        }
        second.audioCuts = original.audioCuts.compactMap { cut in
            if cut.startTime >= localSplit {
                return TimelineCut(startTime: cut.startTime - localSplit, endTime: cut.endTime - localSplit)
            }
            if cut.endTime <= localSplit { return nil }
            return TimelineCut(startTime: 0, endTime: cut.endTime - localSplit)
        }

        assets[idx] = first
        assets.insert(second, at: idx + 1)

        // Re-generate thumbnails for both halves
        let firstID = first.id
        let firstURL = first.url
        let firstStart = first.sourceStartOffset
        let firstDur = first.sourceDuration
        let secondID = second.id
        let secondURL = second.url
        let secondStart = second.sourceStartOffset
        let secondDur = second.sourceDuration

        Task {
            let thumbsA = await TimelineAsset.generateThumbnails(
                for: firstURL, startOffset: firstStart, duration: firstDur, count: 24
            )
            if let i = self.assets.firstIndex(where: { $0.id == firstID }) {
                self.assets[i].thumbnails = thumbsA
            }
            let thumbsB = await TimelineAsset.generateThumbnails(
                for: secondURL, startOffset: secondStart, duration: secondDur, count: 24
            )
            if let i = self.assets.firstIndex(where: { $0.id == secondID }) {
                self.assets[i].thumbnails = thumbsB
            }
        }

        compositionDirty = true
        return true
    }

    /// True if the selected track can be split at the current playhead position.
    var canSplitAtPlayhead: Bool {
        guard let ref = selectedTrack,
              let asset = assets.first(where: { $0.id == ref.assetID })
        else { return false }
        let local = playheadTime - asset.offset
        return local > 0.05 && local < asset.sourceDuration - 0.05
    }

    // MARK: - Selection

    func selectTrack(_ ref: TrackRef) {
        selectedTrack = ref
        selectionStart = nil
        selectionEnd = nil
    }

    func clearTrackSelection() {
        selectedTrack = nil
        selectionStart = nil
        selectionEnd = nil
    }

    func markStart() {
        guard selectedTrack != nil else { return }
        selectionStart = playheadTime
        if let end = selectionEnd, end <= playheadTime {
            selectionEnd = nil
        }
    }

    func markEnd() {
        guard selectedTrack != nil else { return }
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

    // MARK: - Cuts

    /// Cut the currently selected track using selectionStart..selectionEnd (timeline time).
    func deleteSelection() {
        guard let ref = selectedTrack,
              let s = selectionStart, let e = selectionEnd,
              e > s,
              let idx = assets.firstIndex(where: { $0.id == ref.assetID })
        else { return }

        let asset = assets[idx]
        // Convert timeline time → source-local time, clamped to [0, sourceDuration]
        let localStart = max(0, s - asset.offset)
        let localEnd = min(asset.sourceDuration, e - asset.offset)
        if localEnd <= localStart { return }

        let newCut = TimelineCut(startTime: localStart, endTime: localEnd)
        switch ref.kind {
        case .video:
            assets[idx].videoCuts = mergeCut(newCut, into: assets[idx].videoCuts)
        case .audio:
            assets[idx].audioCuts = mergeCut(newCut, into: assets[idx].audioCuts)
        }
        selectionStart = nil
        selectionEnd = nil
        compositionDirty = true
    }

    private func mergeCut(_ newCut: TimelineCut, into existing: [TimelineCut]) -> [TimelineCut] {
        var merged = newCut
        var remaining: [TimelineCut] = []
        for cut in existing {
            if cut.startTime <= merged.endTime && cut.endTime >= merged.startTime {
                merged = TimelineCut(
                    startTime: min(cut.startTime, merged.startTime),
                    endTime: max(cut.endTime, merged.endTime)
                )
            } else {
                remaining.append(cut)
            }
        }
        remaining.append(merged)
        remaining.sort { $0.startTime < $1.startTime }
        return remaining
    }

    func removeCut(assetID: UUID, kind: TrackKind, cutID: UUID) {
        guard let idx = assets.firstIndex(where: { $0.id == assetID }) else { return }
        switch kind {
        case .video:
            assets[idx].videoCuts.removeAll { $0.id == cutID }
        case .audio:
            assets[idx].audioCuts.removeAll { $0.id == cutID }
        }
        compositionDirty = true
    }

    func removeAllCuts() {
        for i in assets.indices {
            assets[i].videoCuts.removeAll()
            assets[i].audioCuts.removeAll()
        }
        compositionDirty = true
    }

    var totalCutCount: Int {
        assets.reduce(0) { $0 + $1.videoCuts.count + $1.audioCuts.count }
    }

    // MARK: - Playback

    func seek(to time: Double) {
        let clamped = max(0, min(time, totalDuration))
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
            return
        }
        // Ensure preview composition is current
        Task {
            await ensurePreviewComposition()
            if playheadTime >= totalDuration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func ensurePreviewComposition() async {
        if !compositionDirty, player.currentItem != nil { return }
        do {
            let (comp, videoComp, audioMix, _, _) = try await TimelineComposer.buildComposition(
                assets: assets,
                musicURL: preparedMusicURL
            )
            // Pass an immutable copy so AVPlayer doesn't track in-flight mutations.
            let immutableAsset = (comp.copy() as? AVAsset) ?? comp
            let item = AVPlayerItem(asset: immutableAsset)
            item.videoComposition = (videoComp?.copy() as? AVVideoComposition) ?? videoComp
            item.audioMix = (audioMix?.copy() as? AVAudioMix) ?? audioMix
            player.replaceCurrentItem(with: item)
            compositionDirty = false
        } catch {
            audioError = "Preview build failed: \(error.localizedDescription)"
        }
    }

    /// Mark that the composition needs rebuilding on next play (called from views after edits).
    func markCompositionDirty() {
        compositionDirty = true
    }

    // MARK: - Audio music (unchanged behavior)

    func setAudioChoice(_ choice: AudioTrackChoice) {
        stopPreview()
        audioError = nil
        audioChoice = choice

        switch choice {
        case .none:
            preparedMusicURL = nil
            markCompositionDirty()
        case .preset(let preset):
            isPreparingAudio = true
            Task {
                do {
                    let url = try await AudioTrackGenerator.ensureTrack(preset)
                    self.preparedMusicURL = url
                } catch {
                    self.preparedMusicURL = nil
                    self.audioError = "Could not prepare track: \(error.localizedDescription)"
                }
                self.isPreparingAudio = false
                self.markCompositionDirty()
            }
        case .custom(let url):
            preparedMusicURL = url
            markCompositionDirty()
        }
    }

    func chooseCustomMP3() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Audio File"
        panel.allowedContentTypes = [.mp3, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setAudioChoice(.custom(url))
    }

    func togglePreview() {
        if isPreviewingAudio {
            stopPreview()
            return
        }
        guard let url = preparedMusicURL else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.prepareToPlay()
            p.play()
            previewPlayer = p
            isPreviewingAudio = true
        } catch {
            audioError = "Could not play preview: \(error.localizedDescription)"
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewingAudio = false
    }

    var hasMusicSelected: Bool {
        preparedMusicURL != nil
    }

    // MARK: - Export

    func exportTrimmedVideo() async throws -> URL {
        isProcessing = true
        processingMessage = "Composing timeline\u{2026}"
        defer { isProcessing = false }

        // If only one asset, no cuts, no music — fast path: return original URL.
        if assets.count == 1, totalCutCount == 0, preparedMusicURL == nil,
           assets[0].offset == 0 {
            return assets[0].url
        }

        return try await TimelineComposer.exportTimeline(
            assets: assets,
            musicURL: preparedMusicURL
        )
    }

    // MARK: - Helpers

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }

    // MARK: - Legacy API used elsewhere (cut list display, etc.)

    /// Total removed time across all tracks (seconds).
    var removedDuration: Double {
        var total: Double = 0
        for a in assets {
            for c in a.videoCuts { total += c.duration }
            for c in a.audioCuts { total += c.duration }
        }
        return total
    }
}
