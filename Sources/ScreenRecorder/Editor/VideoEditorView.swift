import SwiftUI
import AVKit

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel
    var onApply: (URL) async throws -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    // Video preview
                    VideoPlayerView(player: model.player)
                        .frame(minHeight: 200, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    playbackControls

                    // Multi-track timeline
                    TimelineView(model: model)

                    selectionControls

                    cutList

                    audioControls
                }
                .padding(20)
            }

            Divider()
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 720, minHeight: 600)
        .disabled(model.isProcessing)
        .overlay {
            if model.isProcessing {
                processingOverlay
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Video Editor")
                .font(.title2)
                .fontWeight(.semibold)
            Text("(\(model.assets.count) \(model.assets.count == 1 ? "track" : "tracks"))")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Timeline: \(model.formatTime(model.totalDuration))")
                    .font(.callout)
                    .foregroundColor(.secondary)
                if model.removedDuration > 0 {
                    Text("Removed: \(model.formatTime(model.removedDuration))")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Playback

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(action: { model.seek(to: 0) }) {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)

            Button(action: { model.togglePlayPause() }) {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Button(action: { model.seek(to: model.totalDuration) }) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(model.formatTime(model.playheadTime))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
            Text("/")
                .foregroundColor(.secondary)
            Text(model.formatTime(model.totalDuration))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Selection controls

    private var selectionControls: some View {
        VStack(spacing: 8) {
            // Selected track indicator
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .foregroundColor(.secondary)
                if let ref = model.selectedTrack,
                   let asset = model.assets.first(where: { $0.id == ref.assetID }) {
                    Text("Cutting on:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(asset.name) (\(ref.kind == .video ? "video" : "audio"))")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                } else {
                    Text("Click a track in the timeline to enable cuts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: { model.markStart() }) {
                    Label("Mark Start", systemImage: "arrow.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(model.selectedTrack == nil)

                Button(action: { model.markEnd() }) {
                    Label("Mark End", systemImage: "arrow.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(model.selectedTrack == nil)

                Button(action: { model.deleteSelection() }) {
                    Label("Cut Selection", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.hasValidSelection)
            }

            HStack(spacing: 12) {
                Button(action: { model.splitSelectedTrackAtPlayhead() }) {
                    Label("Cut at Cursor", systemImage: "scissors.badge.ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(!model.canSplitAtPlayhead)
                .help("Split the selected track into two pieces at the current playhead position")
                Spacer().frame(maxWidth: .infinity)
                Spacer().frame(maxWidth: .infinity)
            }

            if let start = model.selectionStart, let end = model.selectionEnd, end > start {
                HStack {
                    Text("Selected: \(model.formatTime(start)) → \(model.formatTime(end))")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("(\(String(format: "%.1fs", end - start)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { model.clearSelection() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Cut list

    @ViewBuilder
    private var cutList: some View {
        if model.totalCutCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Removed Segments (\(model.totalCutCount))")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Undo All") { model.removeAllCuts() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }

                ForEach(model.assets) { asset in
                    if !asset.videoCuts.isEmpty || !asset.audioCuts.isEmpty {
                        ForEach(asset.videoCuts) { cut in
                            cutRow(asset: asset, kind: .video, cut: cut)
                        }
                        ForEach(asset.audioCuts) { cut in
                            cutRow(asset: asset, kind: .audio, cut: cut)
                        }
                    }
                }
            }
        }
    }

    private func cutRow(asset: TimelineAsset, kind: TrackKind, cut: TimelineCut) -> some View {
        HStack {
            Image(systemName: kind == .video ? "film" : "waveform")
                .foregroundColor(.red)
                .font(.caption)
            Text("\(asset.name) (\(kind.rawValue))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .leading)
            Text("\(model.formatTime(cut.startTime)) → \(model.formatTime(cut.endTime))")
                .font(.system(.caption, design: .monospaced))
            Text("(\(cut.durationText))")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { model.removeCut(assetID: asset.id, kind: kind, cutID: cut.id) }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Restore this segment")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Color.red.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Audio controls (music)

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
                Text("Background Music")
                    .font(.headline)
                    .foregroundColor(.secondary)
                if model.isPreparingAudio {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("preparing\u{2026}")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                presetButton(title: "None", isSelected: model.audioChoice == .none) {
                    model.setAudioChoice(.none)
                }
                ForEach(AudioPreset.allCases) { preset in
                    presetButton(
                        title: preset.displayName,
                        isSelected: model.audioChoice == .preset(preset)
                    ) {
                        model.setAudioChoice(.preset(preset))
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: { model.chooseCustomMP3() }) {
                    Label(customButtonLabel, systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { model.togglePreview() }) {
                    Label(
                        model.isPreviewingAudio ? "Stop" : "Preview",
                        systemImage: model.isPreviewingAudio ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!model.hasMusicSelected || model.isPreparingAudio)
            }

            if let err = model.audioError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private var customButtonLabel: String {
        if case .custom(let url) = model.audioChoice {
            return url.lastPathComponent
        }
        return "Use My MP3\u{2026}"
    }

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button(action: {
                Task {
                    do {
                        let url = try await model.exportTrimmedVideo()
                        try await onApply(url)
                    } catch {
                        // surfaced via parent state
                    }
                }
            }) {
                applyButtonLabel
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingAudio || model.isAddingAsset)
        }
    }

    private var applyButtonLabel: some View {
        let cutCount = model.totalCutCount
        let trackCount = model.assets.count
        let hasMusic = model.hasMusicSelected
        let text: String
        if trackCount <= 1 && cutCount == 0 && !hasMusic {
            text = "Done"
        } else {
            var parts: [String] = []
            if trackCount > 1 { parts.append("\(trackCount) tracks") }
            if cutCount > 0 { parts.append("\(cutCount) cut\(cutCount == 1 ? "" : "s")") }
            if hasMusic { parts.append("music") }
            text = "Apply " + parts.joined(separator: " + ") + " & Done"
        }
        return Label(text, systemImage: "checkmark.circle")
    }

    // MARK: - Processing overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(model.processingMessage)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}
