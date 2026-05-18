# Screen Recorder

A native macOS screen recording application with a built-in video editor. Select any region of your screen, record it, trim out unwanted sections on a timeline, then export as MP4, MPEG-4, or animated GIF.

<img width="200" height="300" alt="image" src="https://github.com/user-attachments/assets/991c521f-fc7f-4b1c-8d77-31e96ea5f2a1" />
<img width="500"  alt="image" src="https://github.com/user-attachments/assets/901eec50-de0d-415d-8ec5-1cdf1446a7e7" />



Built with Swift, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, and ImageIO — no external dependencies.

## Features

- **Region selection** — fullscreen overlay with click-and-drag to select any rectangle. Multi-display aware.
- **High-quality recording** — captures the selected region at 30 fps using Apple's modern ScreenCaptureKit, hardware-accelerated H.264 encoding.
- **Open existing video files** — load any MP4, MPEG, or GIF from disk into the editor for trimming and re-exporting (GIFs are auto-converted to MP4 for editing).
- **Built-in video editor**
  - Video preview player with play/pause/skip controls (Space bar shortcut)
  - Timeline with thumbnail strip extracted from the recording
  - Drag on the timeline to select a range, or use "Mark Start" / "Mark End" buttons at the playhead position
  - "Cut Selection" to mark segments for deletion (shown in red with diagonal stripes)
  - Undo individual cuts or undo all
  - Live "Final duration" / "Removing X seconds" preview
  - Applies cuts using `AVMutableComposition` to produce a clean trimmed video
- **Three export formats**
  - **MP4** — H.264, modern container, best compatibility
  - **MPEG-4** — same codec, `.mpeg` extension
  - **GIF** — animated, 10 fps, max 640 px wide (smaller files), infinite loop
- **3-second countdown** before recording starts
- **Real-time duration display** while recording

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0+ toolchain (Swift 5.9+ may work after adjusting `Package.swift`)
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode is *not* required

## Build & Install

```sh
git clone https://github.com/moritzzzzz/screen_recorder_mp4_gif.git
cd custom_screen_recorder
bash Scripts/build.sh
open ScreenRecorder.app
```

The script compiles the Swift package in release mode, assembles a proper `.app` bundle in the project root, and applies an ad-hoc code signature (required for macOS to remember the screen-recording permission grant).

To install system-wide:

```sh
cp -R ScreenRecorder.app /Applications/
```

### First Launch

On first launch, macOS will prompt for **Screen Recording permission**. Grant it under:

> System Settings → Privacy & Security → Screen Recording → enable Screen Recorder

You may need to quit and relaunch the app after granting permission.

## Usage

### Record a new clip

1. Launch the app.
2. Pick an **Export Format** (MP4 / MPEG-4 / GIF).
3. Click **Select Region** and drag to choose the area to record (Escape to cancel).
4. Click **Start Recording** — there is a 3-second countdown.
5. Click **Stop Recording** when finished.
6. Optionally click **Edit Video** to trim out sections:
   - Drag on the timeline to select a range
   - Click **Cut Selection** to remove it
   - Repeat for multiple cuts, then click **Apply & Done**
7. Click **Save As ...** to export to your chosen format and location.

### Edit an existing file

1. On the main screen, click **Open Video to Edit…** under the "or" divider.
2. Choose an `.mp4`, `.mpeg`/`.mpg`, `.mov`, or `.gif` file. GIFs are automatically converted to MP4 in the background so the editor can play them.
3. Click **Edit Video** to open the editor (same workflow as above), or skip straight to **Save As ...** to just re-encode to a different format.

## Project Structure

```
custom_screen_recorder/
├── Package.swift                              # Swift Package manifest
├── Sources/ScreenRecorder/
│   ├── App/
│   │   ├── main.swift                         # NSApplication bootstrap
│   │   └── AppDelegate.swift                  # Window + menu bar setup
│   ├── UI/
│   │   ├── ContentView.swift                  # Main state-driven SwiftUI view
│   │   └── ExportFormatPicker.swift           # MP4 / MPEG-4 / GIF segmented picker
│   ├── RegionSelection/
│   │   ├── RegionSelectionController.swift    # Overlay lifecycle, coordinate conversion
│   │   ├── RegionSelectionWindow.swift        # Borderless transparent NSWindow
│   │   └── RegionSelectionView.swift          # Mouse tracking + rubber-band drawing
│   ├── Recording/
│   │   ├── ScreenRecorderViewModel.swift      # @MainActor central state coordinator
│   │   ├── CaptureEngine.swift                # ScreenCaptureKit SCStream + SCStreamOutput
│   │   └── VideoWriter.swift                  # AVAssetWriter wrapper for H.264 MP4
│   ├── Editor/
│   │   ├── VideoEditorModel.swift             # Editor state (thumbnails, cuts, playhead)
│   │   ├── VideoEditorView.swift              # Main editor SwiftUI layout
│   │   ├── TimelineView.swift                 # Canvas-based timeline (thumbnails, cuts, selection, playhead)
│   │   ├── VideoPlayerView.swift              # AVPlayerView NSViewRepresentable
│   │   ├── VideoTrimmer.swift                 # AVMutableComposition + AVAssetExportSession trimming
│   │   └── GIFConverter.swift                 # GIF → MP4 conversion for editing imported GIFs
│   ├── Export/
│   │   ├── ExportManager.swift                # NSSavePanel + format dispatch
│   │   └── GIFExporter.swift                  # AVAssetImageGenerator → CGImageDestination
│   ├── Models/
│   │   ├── RecordingState.swift               # State enum: idle/selectingRegion/recording/done/editing/...
│   │   └── ExportFormat.swift                 # MP4 / MPEG-4 / GIF
│   └── Utilities/
│       └── PermissionManager.swift            # CGPreflight/Request screen-capture access
├── Resources/
│   └── Info.plist                             # Bundle metadata, NSScreenCaptureUsageDescription
└── Scripts/
    └── build.sh                               # swift build + .app assembly + codesign
```

## How It Works

- **Recording.** `CaptureEngine` configures an `SCStream` with `SCContentFilter` for the chosen display and `sourceRect` set to the selected region (converted from NSScreen bottom-left coordinates to ScreenCaptureKit top-left). Frames are forwarded as `CMSampleBuffer`s to `VideoWriter`, which writes them through `AVAssetWriter` with H.264 encoding to a temp `.mp4`.
- **Editing.** `VideoEditorModel` loads the temp video, extracts 30 thumbnail frames via `AVAssetImageGenerator`, and owns playback state (`AVPlayer`) plus a list of `CutRange`s. The timeline is drawn with SwiftUI `Canvas` for performance. When the user applies cuts, `VideoTrimmer` builds an `AVMutableComposition` of the kept segments and exports a new MP4 with `AVAssetExportSession`.
- **Export.** MP4/MPEG-4 are direct file copies (the recording is already H.264 MP4). GIF uses `AVAssetImageGenerator` to extract frames at 10 fps, then `CGImageDestination` (ImageIO) writes them with per-frame delay and infinite-loop properties.


## Known Limitations

- **Video only** — no audio recording (system audio or microphone). Adding audio would require a second `SCStream` output type and an audio `AVAssetWriterInput`.
- **MPEG-4 ≠ MPEG-1/2** — the "MPEG-4" export uses H.264 in an MP4 container with a `.mpeg` extension. macOS does not natively encode legacy MPEG-1/2.
- **GIF defaults are fixed** — 10 fps, 640 px max width. Tune the constants in `GIFExporter.swift` if needed.
- **Permission persistence** — the ad-hoc code signature ties the screen-recording permission to the exact bundle. Rebuilding produces a new signature, so macOS may re-prompt. For wider distribution, sign with a Developer ID certificate and notarize.

## License

MIT — see [LICENSE](LICENSE).
