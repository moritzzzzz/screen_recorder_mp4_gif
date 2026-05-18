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
- **Add a music track to your video**
  - Three built-in tracks — **Calm**, **Adventurous**, **Electronic** — procedurally synthesized in Swift, so they're free for any use (including commercial). Generated on first use and cached locally.
  - Or load your own **MP3** as the audio source.
  - Preview button to hear the track before committing.
  - Audio is auto-looped to match the (possibly trimmed) video length.
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

You don't have to record something new — any video you have on disk can be loaded into the editor for trimming, music-track addition, and format conversion.

1. On the main screen, click **Open Video to Edit…** (below the "or" divider).
2. Choose a video file. Supported formats:
   - `.mp4` and `.m4v` — H.264 MP4 (anything QuickTime can play).
   - `.mpeg` / `.mpg` — MPEG-4 in `.mpeg` container.
   - `.mov` — QuickTime movie.
   - `.gif` — animated GIFs are automatically converted to MP4 on the fly (using `ImageIO` to read frames and `AVAssetWriter` to re-encode to H.264). Frame timing from the GIF is preserved; the original file is left untouched.
3. The app switches to the "Video Loaded" view showing the source filename and total duration.
4. From here you can:
   - Click **Edit Video** to open the editor (trim cuts, add audio — see below).
   - Or click **Save As ...** directly to re-encode the video to a different format (e.g. a GIF to an MP4 or vice versa) without editing.

### Add background music

The video editor can mix a music track into the final output. The video preview itself stays silent — the audio is rendered into the file you export.

1. Open the editor (either from a fresh recording or a loaded video).
2. Find the **Audio Track** panel near the bottom.
3. Pick one of:
   - **None** (default) — no music, the output stays silent.
   - **Calm** — slow C-major sine pad with a soft arpeggio (70 BPM).
   - **Adventurous** — A-minor square-wave bass + sawtooth lead melody + light kick drum (110 BPM).
   - **Electronic** — A-minor 4-on-the-floor kick, filtered-noise hi-hat, syncopated bass, sawtooth arpeggio (124 BPM).
   - **Use My MP3…** — pick any audio file (`.mp3` or other audio format the system can decode) from disk.
4. The first time you pick a built-in track, the app synthesizes it in Swift (~5–10 seconds) and caches it locally at `~/Library/Caches/com.custom.screenrecorder/audio/<name>.m4a`. Subsequent selections are instant.
5. Click **Preview** to hear the chosen track on loop. Click again to stop.
6. Click **Apply & Done** (or "Apply Cuts + Audio & Done" if you also made cuts). The app builds a new MP4 with:
   - Any cuts applied to the video track
   - The audio looped to match the final video duration
   - A **1-second fade-in at the start** and a **1-second fade-out at the end** (both shrink proportionally if the video is shorter than 2 seconds)
7. Export to MP4, MPEG-4, or GIF as usual. Note: GIF export strips the audio (GIFs do not carry sound).

The built-in tracks are mathematically generated from oscillators and envelopes — they are not derived from any copyrighted recording, so the resulting videos are safe for any use including commercial.

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
│   │   ├── VideoTrimmer.swift                 # AVMutableComposition + AVAssetExportSession (video + optional audio)
│   │   ├── GIFConverter.swift                 # GIF → MP4 conversion for editing imported GIFs
│   │   ├── AudioTrack.swift                   # AudioTrackChoice / AudioPreset enums
│   │   └── AudioTrackGenerator.swift          # Procedural music synthesis (calm / adventurous / electronic) → AAC M4A
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
- **Loading existing videos.** Non-GIF files are copied to a temp working directory and handed to the editor unchanged. GIFs go through `GIFConverter`: `CGImageSource` reads each frame and its delay metadata, then `AVAssetWriterInputPixelBufferAdaptor` re-encodes the frames as H.264 in an `.mp4` with the original per-frame timing preserved.
- **Editing.** `VideoEditorModel` loads the temp video, extracts 30 thumbnail frames via `AVAssetImageGenerator`, and owns playback state (`AVPlayer`) plus a list of `CutRange`s. The timeline is drawn with SwiftUI `Canvas` for performance. When the user applies cuts, `VideoTrimmer` builds an `AVMutableComposition` of the kept segments and exports a new MP4 with `AVAssetExportSession`.
- **Audio tracks.** Built-in tracks are synthesized offline by `AudioTrackGenerator`. Sine/square/sawtooth oscillators plus ADSR envelopes render ~3 minutes of stereo 32-bit-float PCM into a `[Float]`, which is fed in 4096-frame chunks through `CMBlockBuffer` + `CMSampleBuffer` into an `AVAssetWriterInput` configured for AAC, producing a small M4A file in the user Caches directory. When the user applies cuts, `VideoTrimmer` adds the audio source as a second composition track and loops it (via repeated `insertTimeRange` calls from `t=0`) until it covers the trimmed video duration. An `AVMutableAudioMix` adds two volume ramps — `0→1` over the first second (fade-in) and `1→0` over the last second (fade-out) — so the music doesn't start or stop abruptly.
- **Export.** MP4/MPEG-4 are direct file copies (the editor's intermediate output is already H.264 MP4 with the chosen audio mixed in). GIF uses `AVAssetImageGenerator` to extract frames at 10 fps, then `CGImageDestination` (ImageIO) writes them with per-frame delay and infinite-loop properties. GIFs cannot carry audio, so any audio track is dropped during GIF export.


## Known Limitations

- **No live audio capture** — the recording itself is video-only; the app does not capture system audio or the microphone during a screen recording. (You can, however, mix in a music track in the editor afterwards — see the "Add background music" section.) Adding live capture would require a second `SCStream` output type and an audio `AVAssetWriterInput`.
- **Built-in music is synthesizer-style** — Calm/Adventurous/Electronic are procedurally generated with basic oscillators, so they have a chiptune/synth character rather than real-instrument timbres. Tracks are 3 minutes long and loop; the loop is unobtrusive for typical screen recordings but may become noticeable for very long videos. Use **Use My MP3…** for orchestral or recorded music.
- **MPEG-4 ≠ MPEG-1/2** — the "MPEG-4" export uses H.264 in an MP4 container with a `.mpeg` extension. macOS does not natively encode legacy MPEG-1/2.
- **GIF defaults are fixed** — 10 fps, 640 px max width. Tune the constants in `GIFExporter.swift` if needed.
- **Permission persistence** — the ad-hoc code signature ties the screen-recording permission to the exact bundle. Rebuilding produces a new signature, so macOS may re-prompt. For wider distribution, sign with a Developer ID certificate and notarize.

## License

MIT — see [LICENSE](LICENSE).
