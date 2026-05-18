import SwiftUI
import AVKit

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel
    var onApply: (URL) async throws -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            VStack(spacing: 16) {
                // Video preview
                VideoPlayerView(player: model.player)
                    .frame(minHeight: 200, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                // Playback controls
                playbackControls

                // Timeline
                TimelineView(model: model)

                // Time labels
                timeLabels

                // Selection controls
                selectionControls

                // Cut list
                cutList

                // Audio track controls
                audioControls

                Spacer(minLength: 0)

                // Bottom action bar
                bottomBar
            }
            .padding(20)
        }
        .frame(minWidth: 650, minHeight: 550)
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

            Spacer()

            if !model.cutRanges.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Final duration: \(model.formatTime(model.trimmedDuration))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Removing: \(model.formatTime(model.removedDuration))")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else {
                Text("Duration: \(model.formatTime(model.duration))")
                    .font(.callout)
                    .foregroundColor(.secondary)
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

            Button(action: { model.seek(to: model.duration) }) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(model.formatTime(model.playheadTime))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
            Text("/")
                .foregroundColor(.secondary)
            Text(model.formatTime(model.duration))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Time labels

    private var timeLabels: some View {
        HStack {
            Text(model.formatTime(0))
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(model.formatTime(model.duration))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, -12)
    }

    // MARK: - Selection controls

    private var selectionControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Mark start
                Button(action: { model.markStart() }) {
                    Label("Mark Start", systemImage: "arrow.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)

                // Mark end
                Button(action: { model.markEnd() }) {
                    Label("Mark End", systemImage: "arrow.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)

                // Delete selection
                Button(action: { model.deleteSelection() }) {
                    Label("Cut Selection", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.hasValidSelection)
            }

            // Selection info
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
        if !model.cutRanges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Removed Segments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Undo All") { model.removeAllCuts() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }

                ForEach(model.cutRanges) { cut in
                    HStack {
                        Image(systemName: "scissors")
                            .foregroundColor(.red)
                            .font(.caption)

                        Text("\(model.formatTime(cut.startTime)) → \(model.formatTime(cut.endTime))")
                            .font(.system(.callout, design: .monospaced))

                        Text("(\(cut.durationText))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { model.removeCut(cut) }) {
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
            }
        }
    }

    // MARK: - Audio controls

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
                Text("Audio Track")
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

            // Preset picker
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

            // Custom + preview row
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
                .disabled(!model.hasAudioSelected || model.isPreparingAudio)
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
            Button("Cancel") {
                onCancel()
            }
            .controlSize(.large)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(action: {
                Task {
                    do {
                        let url = try await model.exportTrimmedVideo()
                        try await onApply(url)
                    } catch {
                        // Error handled by caller
                    }
                }
            }) {
                applyButtonLabel
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingAudio)
        }
    }

    private var applyButtonLabel: some View {
        let hasCuts = !model.cutRanges.isEmpty
        let hasAudio = model.hasAudioSelected
        let text: String
        if !hasCuts && !hasAudio {
            text = "Done"
        } else if hasCuts && !hasAudio {
            text = "Apply \(model.cutRanges.count) Cut\(model.cutRanges.count == 1 ? "" : "s") & Done"
        } else if !hasCuts && hasAudio {
            text = "Add Audio & Done"
        } else {
            text = "Apply Cuts + Audio & Done"
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
                Text("Applying cuts...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}
