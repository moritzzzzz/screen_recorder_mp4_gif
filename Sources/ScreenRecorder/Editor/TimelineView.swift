import SwiftUI
import AppKit

struct TimelineView: View {
    @ObservedObject var model: VideoEditorModel

    private let headerWidth: CGFloat = 130
    private let videoLaneHeight: CGFloat = 56
    private let audioLaneHeight: CGFloat = 28
    private let rulerHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            timeRuler
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    ForEach(model.assets) { asset in
                        assetSection(asset: asset)
                    }
                    addVideoRow
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            .background(Color.black.opacity(0.12))
            .cornerRadius(8)
        }
    }

    // MARK: - Time Ruler

    private var timeRuler: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width - headerWidth
            let total = max(1, model.totalDuration)
            HStack(spacing: 0) {
                Color.clear.frame(width: headerWidth)
                ZStack(alignment: .topLeading) {
                    // Tick marks
                    Canvas { ctx, size in
                        let interval = niceTickInterval(for: total)
                        var t: Double = 0
                        while t <= total + 0.01 {
                            let x = CGFloat(t / total) * size.width
                            let path = Path { p in
                                p.move(to: CGPoint(x: x, y: 0))
                                p.addLine(to: CGPoint(x: x, y: 6))
                            }
                            ctx.stroke(path, with: .color(.secondary), lineWidth: 1)
                            // Label
                            let label = model.formatTime(t)
                            ctx.draw(Text(label).font(.system(size: 9)).foregroundColor(.secondary),
                                     at: CGPoint(x: x + 2, y: 12))
                            t += interval
                        }
                    }
                    // Playhead in ruler
                    let phX = CGFloat(model.playheadTime / total) * totalWidth
                    Triangle()
                        .fill(Color.white)
                        .frame(width: 10, height: 8)
                        .offset(x: phX - 5, y: 0)
                }
                .frame(width: totalWidth, height: rulerHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let frac = max(0, min(g.location.x / totalWidth, 1))
                            model.seek(to: frac * total)
                        }
                )
            }
        }
        .frame(height: rulerHeight)
    }

    private func niceTickInterval(for total: Double) -> Double {
        if total <= 10 { return 1 }
        if total <= 30 { return 5 }
        if total <= 120 { return 10 }
        if total <= 600 { return 30 }
        return 60
    }

    // MARK: - Asset Section (1 video lane + optional audio lane)

    private func assetSection(asset: TimelineAsset) -> some View {
        VStack(spacing: 1) {
            laneRow(
                asset: asset,
                kind: .video,
                height: videoLaneHeight,
                isPrimary: model.assets.first?.id == asset.id
            )
            if asset.hasAudio {
                laneRow(
                    asset: asset,
                    kind: .audio,
                    height: audioLaneHeight,
                    isPrimary: false
                )
            }
        }
    }

    private func laneRow(
        asset: TimelineAsset,
        kind: TrackKind,
        height: CGFloat,
        isPrimary: Bool
    ) -> some View {
        let ref = TrackRef(assetID: asset.id, kind: kind)
        let isSelected = model.selectedTrack == ref
        let isEnabled = asset.isEnabled(for: kind)

        return HStack(spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: kind == .video ? "film" : "waveform")
                    .foregroundColor(.secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind == .video ? asset.name : "audio")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if kind == .video {
                        Text(model.formatTime(asset.sourceDuration))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: {
                    model.toggleTrackEnabled(assetID: asset.id, kind: kind)
                }) {
                    Image(systemName: enableIcon(kind: kind, isEnabled: isEnabled))
                        .foregroundColor(isEnabled ? .secondary : .red)
                }
                .buttonStyle(.plain)
                .help(isEnabled
                      ? (kind == .video ? "Disable this video track" : "Mute this audio track")
                      : (kind == .video ? "Enable this video track" : "Unmute this audio track"))
                if kind == .video {
                    Button(action: { model.removeAsset(id: asset.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this video from the timeline")
                }
            }
            .padding(.horizontal, 6)
            .frame(width: headerWidth, height: height)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))
            .cornerRadius(4)
            .onTapGesture {
                model.selectTrack(ref)
            }

            // Lane body
            GeometryReader { geo in
                let total = max(1, model.totalDuration)
                let totalWidth = geo.size.width
                let assetX = CGFloat(asset.offset / total) * totalWidth
                let assetWidth = CGFloat(asset.sourceDuration / total) * totalWidth

                ZStack(alignment: .topLeading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .frame(width: totalWidth, height: height)
                        .cornerRadius(4)

                    // Asset content strip (dimmed when disabled)
                    laneContent(asset: asset, kind: kind, height: height)
                        .opacity(isEnabled ? 1.0 : 0.25)
                        .saturation(isEnabled ? 1.0 : 0.0)
                        .frame(width: max(2, assetWidth), height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                        )
                        .overlay(
                            // Diagonal "off" hatch across entire asset strip when disabled
                            Group {
                                if !isEnabled {
                                    Canvas { ctx, size in
                                        let step: CGFloat = 8
                                        var px: CGFloat = -size.height
                                        while px < size.width + size.height {
                                            let p = Path { path in
                                                path.move(to: CGPoint(x: px, y: 0))
                                                path.addLine(to: CGPoint(x: px + size.height, y: size.height))
                                            }
                                            ctx.stroke(p, with: .color(.red.opacity(0.55)), lineWidth: 1)
                                            px += step
                                        }
                                    }
                                }
                            }
                        )
                        .offset(x: assetX)

                    // Cuts (rendered relative to the asset's strip position)
                    cutOverlays(asset: asset, kind: kind, height: height, total: total, totalWidth: totalWidth)

                    // Selection overlay (only on selected lane)
                    if isSelected,
                       let s = model.selectionStart, let e = model.selectionEnd, e > s {
                        let sx = CGFloat(s / total) * totalWidth
                        let ex = CGFloat(e / total) * totalWidth
                        Rectangle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: ex - sx, height: height)
                            .offset(x: sx)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: ex - sx, height: height)
                                    .offset(x: sx),
                                alignment: .topLeading
                            )
                            .allowsHitTesting(false)
                    }

                    // Playhead line
                    let phX = CGFloat(model.playheadTime / total) * totalWidth
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: height)
                        .offset(x: phX)
                        .allowsHitTesting(false)
                }
                .frame(width: totalWidth, height: height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let frac = max(0, min(location.x / totalWidth, 1))
                    model.seek(to: frac * total)
                    model.selectTrack(ref)
                }
                .gesture(laneDragGesture(asset: asset, ref: ref, totalWidth: totalWidth, total: total))
                .help(kind == .video
                      ? "Drag to select a cut region · Cmd+drag to move the track · Click to set the playhead"
                      : "Drag to select a cut region on the audio · Cmd+drag (on the video lane above) to move both")
            }
            .frame(height: height)
        }
    }

    private func enableIcon(kind: TrackKind, isEnabled: Bool) -> String {
        if kind == .video {
            return isEnabled ? "eye" : "eye.slash"
        } else {
            return isEnabled ? "speaker.wave.2" : "speaker.slash"
        }
    }

    private func laneDragGesture(
        asset: TimelineAsset,
        ref: TrackRef,
        totalWidth: CGFloat,
        total: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                let cmdHeld = NSEvent.modifierFlags.contains(.command)
                let secondsPerPixel = total / Double(totalWidth)

                if cmdHeld {
                    let deltaSec = Double(g.translation.width) * secondsPerPixel
                    let newOffset = max(0, asset.offset + deltaSec)
                    // Snap tolerance: ~8 pixels worth of time
                    let snapTol = 8.0 * secondsPerPixel
                    model.setOffset(forAssetID: asset.id, offset: newOffset, snapTolerance: snapTol)
                } else {
                    // Selection drag: auto-select the lane, then set range in timeline time
                    if model.selectedTrack != ref {
                        model.selectTrack(ref)
                    }
                    let startSec = max(0, min(Double(g.startLocation.x) * secondsPerPixel, total))
                    let endSec = max(0, min(Double(g.location.x) * secondsPerPixel, total))
                    let lo = min(startSec, endSec)
                    let hi = max(startSec, endSec)
                    model.setSelection(start: lo, end: hi)
                }
            }
    }

    @ViewBuilder
    private func laneContent(asset: TimelineAsset, kind: TrackKind, height: CGFloat) -> some View {
        if kind == .video {
            videoLaneContent(asset: asset, height: height)
        } else {
            audioLaneContent(height: height)
        }
    }

    @ViewBuilder
    private func videoLaneContent(asset: TimelineAsset, height: CGFloat) -> some View {
        if asset.thumbnails.isEmpty {
            Rectangle().fill(Color.gray.opacity(0.4))
        } else {
            HStack(spacing: 0) {
                ForEach(0..<asset.thumbnails.count, id: \.self) { i in
                    Image(nsImage: asset.thumbnails[i])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: height)
                        .clipped()
                }
            }
        }
    }

    private func audioLaneContent(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.45), Color.green.opacity(0.25)]),
                startPoint: .top, endPoint: .bottom
            )
            Canvas { ctx, size in
                let bars: Int = 80
                let barW = size.width / CGFloat(bars)
                for i in 0..<bars {
                    let h = CGFloat(0.35 + 0.5 * abs(sin(Double(i) * 0.41)) * abs(sin(Double(i) * 0.17)))
                    let rect = CGRect(
                        x: CGFloat(i) * barW + barW * 0.1,
                        y: (size.height - size.height * h) / 2,
                        width: barW * 0.8,
                        height: size.height * h
                    )
                    ctx.fill(Path(rect), with: .color(.white.opacity(0.35)))
                }
            }
        }
    }

    @ViewBuilder
    private func cutOverlays(
        asset: TimelineAsset,
        kind: TrackKind,
        height: CGFloat,
        total: Double,
        totalWidth: CGFloat
    ) -> some View {
        ForEach(asset.cuts(for: kind)) { cut in
            let timelineStart = asset.offset + cut.startTime
            let timelineEnd = asset.offset + cut.endTime
            let x = CGFloat(timelineStart / total) * totalWidth
            let w = max(2, CGFloat((timelineEnd - timelineStart) / total) * totalWidth)
            cutBox(width: w, height: height)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    private func cutBox(width w: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Opaque dark base — clearly hides the underlying lane content
            Rectangle()
                .fill(Color.black.opacity(0.75))
            // Red tint
            Rectangle()
                .fill(Color.red.opacity(0.55))
            // Diagonal hatching for an unmistakable "removed" look
            Canvas { ctx, size in
                let step: CGFloat = 7
                var px: CGFloat = -size.height
                while px < size.width + size.height {
                    let p = Path { path in
                        path.move(to: CGPoint(x: px, y: 0))
                        path.addLine(to: CGPoint(x: px + size.height, y: size.height))
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.45)), lineWidth: 1)
                    px += step
                }
            }
            // Crisp border
            Rectangle()
                .stroke(Color.red, lineWidth: 1.5)
        }
        .frame(width: w, height: height)
        .cornerRadius(2)
    }

    // MARK: - Add row

    private var addVideoRow: some View {
        HStack {
            Button(action: { model.addVideoFromFile() }) {
                Label("Add Video", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.isAddingAsset)

            if model.isAddingAsset {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
                Text("Loading\u{2026}")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

// Triangle shape was previously in this file too — keep it for compatibility.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
