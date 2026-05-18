import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ScreenRecorderViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .editing:
                editorView
            default:
                mainView
            }
        }
    }

    // MARK: - Main view (non-editor states)

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "record.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text("Screen Recorder")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Content area
            VStack(spacing: 16) {
                switch viewModel.state {
                case .idle:
                    idleView
                case .selectingRegion:
                    selectingView
                case .countingDown(let count):
                    countdownView(count)
                case .recording:
                    recordingView
                case .processing:
                    processingView
                case .done:
                    doneView
                case .error(let message):
                    errorView(message)
                case .editing:
                    EmptyView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 400, minHeight: 550)
    }

    // MARK: - Editor view

    @ViewBuilder
    private var editorView: some View {
        if let editor = viewModel.editorModel {
            VideoEditorView(
                model: editor,
                onApply: { editedURL in
                    viewModel.finishEditing(editedURL: editedURL)
                },
                onCancel: {
                    viewModel.cancelEditing()
                }
            )
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading editor...")
                    .font(.headline)
            }
            .frame(minWidth: 650, minHeight: 550)
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 20) {
            // Format picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Format")
                    .font(.headline)
                    .foregroundColor(.secondary)
                ExportFormatPicker(selection: $viewModel.selectedFormat)
            }

            Spacer()

            // Region info
            if let desc = viewModel.regionDescription {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    Text("Region Selected")
                        .font(.headline)
                    Text(desc)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No region selected")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button(action: { viewModel.selectRegion() }) {
                    Label(viewModel.selectedRegion == nil ? "Select Region" : "Change Region",
                          systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                if viewModel.selectedRegion != nil {
                    Button(action: { viewModel.startRecording() }) {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                // Divider with "or"
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, 2)

                Button(action: { viewModel.openVideoFile() }) {
                    Label("Open Video to Edit\u{2026}", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Load an MP4, MPEG, or GIF file to edit and re-export")
            }
        }
    }

    private var selectingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Select a region on screen...")
                .font(.headline)
            Text("Click and drag to select. Press Escape to cancel.")
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
        }
    }

    private func countdownView(_ count: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("\(count)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundColor(.red)
            Text("Recording starts in...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var recordingView: some View {
        VStack(spacing: 20) {
            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .modifier(PulseAnimation())
                Text("Recording")
                    .font(.headline)
                    .foregroundColor(.red)
            }

            Text(viewModel.formattedDuration)
                .font(.system(size: 48, weight: .medium, design: .monospaced))

            if let desc = viewModel.regionDescription {
                Text(desc)
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button(action: { viewModel.stopRecording() }) {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Processing...")
                .font(.headline)
            Text(processingMessage)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var processingMessage: String {
        if case .loaded = viewModel.videoSource {
            return "Loading video"
        }
        return "Finalizing your recording"
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            // Format picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Format")
                    .font(.headline)
                    .foregroundColor(.secondary)
                ExportFormatPicker(selection: $viewModel.selectedFormat)
            }

            Spacer()

            switch viewModel.videoSource {
            case .recorded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Recording Complete!")
                    .font(.headline)
            case .loaded(let filename):
                Image(systemName: "film.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Video Loaded")
                    .font(.headline)
                Text(filename)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Duration: \(viewModel.formattedDuration)")
                .foregroundColor(.secondary)

            if let url = viewModel.exportedFileURL {
                Text("Saved: \(url.lastPathComponent)")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { viewModel.startEditing() }) {
                        Label("Edit Video", systemImage: "slider.horizontal.below.square.and.square.filled")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button(action: { viewModel.exportRecording() }) {
                        Label("Save As \(viewModel.selectedFormat.rawValue)...", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    if viewModel.exportedFileURL != nil {
                        Button(action: { viewModel.revealInFinder() }) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .controlSize(.large)
                    }

                    Button(action: { viewModel.newRecording() }) {
                        Label("New Recording", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()

            Button(action: { viewModel.reset() }) {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
