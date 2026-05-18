# Screen Recorder

A native macOS screen recording application with a built-in video editor. Select any region of your screen, record it, trim out unwanted sections on a timeline, then export as MP4, MPEG-4, or animated GIF.

<img width="200" height="300" alt="image" src="https://github.com/user-attachments/assets/54269639-1670-410d-9919-fdb0902dc9f2" />
<img width="500"  alt="image" src="https://github.com/user-attachments/assets/d6431777-9352-434b-8e34-9ce3a374d912" />




Built with Swift, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, and ImageIO — no external dependencies.

## Features

- **Region selection** — fullscreen overlay with click-and-drag to select any rectangle. Multi-display aware.
- **High-quality recording** — captures the selected region at 30 fps using Apple's modern ScreenCaptureKit, hardware-accelerated H.264 encoding.
- **Optional live audio capture** — independent toggles on the main screen for **System Audio** (anything your Mac is playing, via ScreenCaptureKit) and **Microphone** (default audio input, via `AVCaptureSession`). Either, both, or neither can be enabled before you start recording. Each enabled source becomes its own audio track in the output MP4.
- **Open existing video files** — load any MP4, MPEG, or GIF from disk into the editor for trimming and re-exporting (GIFs are auto-converted to MP4 for editing).
- **Multi-track video editor**
  - Video preview player with play/pause/skip controls (Space bar shortcut). Press Play to render the current composition.
  - **Multiple video tracks** — add any MP4/MPEG/MOV/GIF via the **+ Add Video** button. Each loaded video becomes a video lane, plus an audio lane if the source has audio.
  - **Drag on a lane = select a cut region** on that lane; **Cmd+drag = move the track** horizontally. Cmd+drag snaps to other tracks' edges and existing cut boundaries.
  - **Composition is layered**: when two video tracks overlap in time, the later-added one is on top; gaps cut into the top track show the lower track through. Audio tracks are mixed together.
  - **Per-track cuts** — every lane has its own cut list. Cuts produce silent / black gaps rather than rippling out time, so cuts on different lanes stay aligned to the timeline (e.g. silence the audio of video 2 while its video keeps playing).
  - **Cut at Cursor** (razor) — split the selected track in two at the playhead so you can move the second half independently.
  - **Enable / disable any track** — eye / speaker toggle on each lane header excludes the track from the composition without losing its cuts or offset.
  - Cut list grouped by track with one-click undo per cut.
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
3. (Optional) Under **Audio Sources**, toggle **System Audio** to record what your Mac is playing and/or **Microphone** to record your voice. The first time you enable Microphone the OS will prompt for permission.
4. Click **Select Region** and drag to choose the area to record (Escape to cancel).
5. Click **Start Recording** — there is a 3-second countdown.
6. Click **Stop Recording** when finished.
7. Optionally click **Edit Video** to trim out sections:
   - Drag on the timeline to select a range
   - Click **Cut Selection** to remove it
   - Repeat for multiple cuts, then click **Apply & Done**
8. Click **Save As ...** to export to your chosen format and location.

### Record system audio and microphone

The recording can include audio in addition to video. Both sources are independent — turn either, both, or neither on **before** you press **Start Recording**.

1. On the main screen, find the **Audio Sources** section under the Export Format picker.
2. Toggle the sources you want:
   - **System Audio** — captures whatever your Mac is playing: music apps, browser playback, app notifications, system sounds. No separate permission is required (it rides on the Screen Recording permission you already granted).
   - **Microphone** — captures the system default audio input (built-in mic, USB mic, headset, etc.). On first use macOS prompts for **Microphone** permission; grant it under *System Settings → Privacy & Security → Microphone* and restart the recording if needed.
3. Pick your region, click **Start Recording**, do your thing, click **Stop Recording**.
4. The temp MP4 now contains:
   - the video track
   - an audio track for System Audio (if enabled)
   - an audio track for Microphone (if enabled)
5. **Save As MP4 / MPEG-4** — the audio travels through to the exported file unchanged. **GIF** still strips audio (GIFs can't carry sound).

**Typical use cases**
- Tutorial with voiceover: turn **Microphone** on.
- Capturing a video call or game audio without your commentary: turn **System Audio** on.
- Demo with both your voice and an app's sound: turn **both** on. The two audio tracks play simultaneously in QuickTime/VLC. (Caveat: the editor's per-asset audio lane only edits the first track for now — see Known Limitations.)
- Silent demo: leave both off (the original behavior).

**Permission troubleshooting**
- If you toggle Microphone on and recording fails with a permission error, open *System Settings → Privacy & Security → Microphone* and make sure **Screen Recorder** is enabled. You may need to quit and relaunch the app after granting.
- If System Audio is silent in the recording, check that your Screen Recording permission is still granted (sometimes a fresh build of the `.app` triggers a re-prompt because the ad-hoc code signature changes).

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

### Compose multiple videos on a timeline

The editor isn't limited to the file you opened — you can layer additional videos on top, slide them around in time, and trim each one independently. The composition you see in the preview is exactly what gets exported.

1. Open the editor (either after a recording or from **Open Video to Edit…**).
2. Click **+ Add Video** at the bottom of the timeline. Pick another `.mp4`, `.mpeg`/`.mpg`, `.mov`, or `.gif`. The new file appears as one or two new lanes (video, plus audio if the source has any) added at the current end of the timeline.
3. Position the track:
   - **Cmd + drag** on a lane to slide that track left or right on the timeline. It snaps to other tracks' start / end positions and to existing cut boundaries (snap tolerance ≈ 8 px).
   - The asset's video and audio sub-lanes share one offset — moving the video lane moves the audio with it.
4. Trim each track independently:
   - **Click** a lane to select it (header turns blue).
   - **Drag** anywhere on the lane to mark a cut region (range is shown in blue). Drag with no Cmd modifier — Cmd is reserved for the move gesture.
   - **Mark Start** / **Mark End** at the playhead are still available if you prefer button-based selection.
   - Click **Cut Selection** — the range becomes a solid red gap on **just that lane**. The other lanes (e.g. the same asset's video) keep playing through.
   - Click **Cut at Cursor** to split the selected track at the playhead into two independent clips you can offset separately. Useful for rearranging a clip's beginning and end.
5. Toggle tracks on/off:
   - Each lane header has an **eye** (video) or **speaker** (audio) icon. Click to disable; the lane goes dim with a red diagonal hatch and is dropped from the export. Click again to re-enable — all cuts and offsets are preserved.
6. **Layering** (z-order) — when two video tracks overlap in time, the later-added one is the visible one. If you cut a hole in the top track, the lane below shows through. To put a track on top, add it later (or use **Cut at Cursor** + move to rearrange).
7. Press **Play** to preview the multi-track composition. The preview rebuilds itself the first time you hit play after any edit, so each play reflects the latest timeline state.
8. Click **Apply … & Done** — the app composes one MP4 that contains all enabled tracks, their offsets, cuts, layering, and (optionally) a music track on top. Then **Save As MP4 / MPEG-4 / GIF** as usual.

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
│   │   ├── VideoEditorModel.swift             # @MainActor central editor state: assets, playhead, selection, music
│   │   ├── VideoEditorView.swift              # Main editor SwiftUI layout
│   │   ├── TimelineAsset.swift                # TimelineAsset / TimelineCut / TrackRef data model + asset loader + thumbnail extraction
│   │   ├── TimelineView.swift                 # Multi-lane timeline view (thumbnails, audio waveform, cuts, selection, playhead, drag/Cmd+drag gestures)
│   │   ├── TimelineComposer.swift             # Builds the AVMutableComposition + AVVideoComposition (layered) + AVAudioMix for preview and export
│   │   ├── VideoPlayerView.swift              # AVPlayerView NSViewRepresentable
│   │   ├── VideoTrimmer.swift                 # Legacy single-track trimmer (kept for reference; superseded by TimelineComposer)
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
- **Audio capture during recording.** When the **System Audio** toggle is on, `SCStreamConfiguration.capturesAudio = true` makes ScreenCaptureKit deliver `.audio` sample buffers through the same stream, which `CaptureEngine` forwards to a dedicated audio `AVAssetWriterInput`. When the **Microphone** toggle is on, a separate `AVCaptureSession` with `AVCaptureAudioDataOutput` feeds mic sample buffers to a second audio writer input. The writer uses a serial dispatch queue for all appends (video + both audio sources) and lazily calls `startSession(atSourceTime:)` on the first sample from any source so the three streams share one timeline anchor.
- **Loading existing videos.** Non-GIF files are copied to a temp working directory and handed to the editor unchanged. GIFs go through `GIFConverter`: `CGImageSource` reads each frame and its delay metadata, then `AVAssetWriterInputPixelBufferAdaptor` re-encodes the frames as H.264 in an `.mp4` with the original per-frame timing preserved.
- **Multi-track editing.** `VideoEditorModel` owns a list of `TimelineAsset`s. Each asset references a source URL plus a `sourceStartOffset` (which slice of the file this asset represents — non-zero after a **Cut at Cursor** split), an `offset` (timeline placement), independent `videoCuts` / `audioCuts` lists, and `videoEnabled` / `audioEnabled` flags. The timeline is rendered as a vertical stack of lanes (video + optional audio) inside a SwiftUI `ScrollView`; each lane is positioned and sized in pixels proportional to its place on the global timeline. Cuts are stored in asset-local time, so moving an asset's offset slides its cuts along with it. Thumbnails are extracted per-asset by `AVAssetImageGenerator` using the `sourceStartOffset` as the starting time so the strip always reflects the right portion of the file.
- **Composition (preview + export).** `TimelineComposer.buildComposition(assets:musicURL:)` constructs one `AVMutableComposition` with one composition video track per enabled asset (preserving its preferred transform) and one composition audio track per enabled asset that has audio, plus one more audio track for the optional looped music. Cuts produce **real gaps** in each composition track: the kept source segments are inserted at `offset + segment.start` in timeline time, leaving silent / transparent holes where cuts were applied — so per-track cuts don't desync sibling lanes. The accompanying `AVMutableVideoComposition` uses **one instruction** covering the entire timeline with one `AVMutableVideoCompositionLayerInstruction` per video track, added in reverse order so later-added assets sit on top of the layer stack. Each layer carries an explicit `setTransform(...)` from its composition track (required for AVPlayer to render multi-track correctly; without it the preview falls back to identity and goes blank). The `AVMutableAudioMix` puts a 1 s fade-in and 1 s fade-out volume ramp on every audio track (including the music). The same composition object is used both for the editor preview (handed to `AVPlayer` via `replaceCurrentItem(with:)` whenever edits invalidate the cache) and for export (handed to `AVAssetExportSession`).
- **Audio tracks.** Built-in music is synthesized offline by `AudioTrackGenerator`. Sine/square/sawtooth oscillators plus ADSR envelopes render ~3 minutes of stereo 32-bit-float PCM into a `[Float]`, which is fed in 4096-frame chunks through `CMBlockBuffer` + `CMSampleBuffer` into an `AVAssetWriterInput` configured for AAC, producing a small M4A file in the user Caches directory. The composer loops the music to fit the timeline via repeated `insertTimeRange` calls from `t=0` until it covers the full duration.
- **Export.** MP4/MPEG-4 are direct file copies (the editor's intermediate output is already H.264 MP4 with the chosen audio mixed in). GIF uses `AVAssetImageGenerator` to extract frames at 10 fps, then `CGImageDestination` (ImageIO) writes them with per-frame delay and infinite-loop properties. GIFs cannot carry audio, so any audio track is dropped during GIF export.


## Known Limitations

- **Two audio sources = two audio tracks in the output.** When both System Audio and Microphone are enabled, the resulting MP4 contains two separate audio tracks. QuickTime and most players mix them together on playback, but the editor's per-asset audio lane only shows the first track — to edit them as separate lanes today you'd need to load the recording back through **Open Video to Edit…** twice (or pick just one source up front). Pre-mixing them into a single track in real time is on the roadmap.
- **Built-in music is synthesizer-style** — Calm/Adventurous/Electronic are procedurally generated with basic oscillators, so they have a chiptune/synth character rather than real-instrument timbres. Tracks are 3 minutes long and loop; the loop is unobtrusive for typical screen recordings but may become noticeable for very long videos. Use **Use My MP3…** for orchestral or recorded music.
- **MPEG-4 ≠ MPEG-1/2** — the "MPEG-4" export uses H.264 in an MP4 container with a `.mpeg` extension. macOS does not natively encode legacy MPEG-1/2.
- **GIF defaults are fixed** — 10 fps, 640 px max width. Tune the constants in `GIFExporter.swift` if needed.
- **Permission persistence** — the ad-hoc code signature ties the screen-recording permission to the exact bundle. Rebuilding produces a new signature, so macOS may re-prompt. For wider distribution, sign with a Developer ID certificate and notarize.

## License

MIT — see [LICENSE](LICENSE).
