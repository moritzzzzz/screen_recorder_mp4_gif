import SwiftUI

struct TimelineView: View {
    @ObservedObject var model: VideoEditorModel
    let height: CGFloat = 68

    @State private var isDragging = false
    @State private var dragStartX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            Canvas { context, size in
                drawThumbnails(context: context, size: size)
                drawCutRanges(context: context, size: size)
                drawSelection(context: context, size: size)
                drawPlayhead(context: context, size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture(totalWidth: w))
        }
        .frame(height: height)
    }

    // MARK: - Drawing

    private func drawThumbnails(context: GraphicsContext, size: CGSize) {
        if model.thumbnails.isEmpty {
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                with: .color(.gray.opacity(0.3))
            )
            return
        }

        let thumbWidth = size.width / CGFloat(model.thumbnails.count)
        for (i, image) in model.thumbnails.enumerated() {
            let x = CGFloat(i) * thumbWidth
            let rect = CGRect(x: x, y: 0, width: thumbWidth, height: size.height)
            context.draw(
                Image(nsImage: image),
                in: rect
            )
        }
    }

    private func drawCutRanges(context: GraphicsContext, size: CGSize) {
        for cut in model.cutRanges {
            let startX = CGFloat(cut.startTime / model.duration) * size.width
            let endX = CGFloat(cut.endTime / model.duration) * size.width
            let rect = CGRect(x: startX, y: 0, width: endX - startX, height: size.height)

            // Red overlay
            context.fill(Path(rect), with: .color(.red.opacity(0.5)))

            // Diagonal stripes
            var stripePath = Path()
            let step: CGFloat = 8
            var x: CGFloat = startX - size.height
            while x < endX + size.height {
                stripePath.move(to: CGPoint(x: x, y: 0))
                stripePath.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += step
            }
            var stripeContext = context
            stripeContext.clip(to: Path(rect))
            stripeContext.stroke(stripePath, with: .color(.red.opacity(0.3)), lineWidth: 1)
        }
    }

    private func drawSelection(context: GraphicsContext, size: CGSize) {
        guard let start = model.selectionStart,
              let end = model.selectionEnd,
              end > start else { return }

        let startX = CGFloat(start / model.duration) * size.width
        let endX = CGFloat(end / model.duration) * size.width
        let rect = CGRect(x: startX, y: 0, width: endX - startX, height: size.height)

        // Selection fill
        context.fill(Path(rect), with: .color(.blue.opacity(0.25)))

        // Selection border
        context.stroke(Path(rect), with: .color(.blue), lineWidth: 2)

        // Left handle
        let handleW: CGFloat = 5
        let leftHandle = CGRect(x: startX - 1, y: 0, width: handleW, height: size.height)
        context.fill(Path(roundedRect: leftHandle, cornerRadius: 2), with: .color(.blue))

        // Right handle
        let rightHandle = CGRect(x: endX - handleW + 1, y: 0, width: handleW, height: size.height)
        context.fill(Path(roundedRect: rightHandle, cornerRadius: 2), with: .color(.blue))
    }

    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        let x = CGFloat(model.playheadTime / model.duration) * size.width

        // Playhead line
        let line = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(line, with: .color(.white), lineWidth: 2)

        // Top triangle indicator
        let triSize: CGFloat = 10
        let triangle = Path { p in
            p.move(to: CGPoint(x: x - triSize / 2, y: 0))
            p.addLine(to: CGPoint(x: x + triSize / 2, y: 0))
            p.addLine(to: CGPoint(x: x, y: triSize * 0.6))
            p.closeSubpath()
        }
        context.fill(triangle, with: .color(.white))

        // Bottom triangle
        let bottomTri = Path { p in
            p.move(to: CGPoint(x: x - triSize / 2, y: size.height))
            p.addLine(to: CGPoint(x: x + triSize / 2, y: size.height))
            p.addLine(to: CGPoint(x: x, y: size.height - triSize * 0.6))
            p.closeSubpath()
        }
        context.fill(bottomTri, with: .color(.white))
    }

    // MARK: - Gesture

    private func dragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let position = max(0, min(value.location.x / totalWidth, 1.0))
                let time = position * model.duration

                if !isDragging {
                    isDragging = true
                    dragStartX = value.startLocation.x
                }

                let dragDistance = abs(value.location.x - (dragStartX ?? value.location.x))

                if dragDistance < 4 {
                    model.seek(to: time)
                } else {
                    let startPos = max(0, min((dragStartX ?? value.startLocation.x) / totalWidth, 1.0))
                    let startTime = startPos * model.duration

                    if time >= startTime {
                        model.setSelection(start: startTime, end: time)
                    } else {
                        model.setSelection(start: time, end: startTime)
                    }
                    model.seek(to: time)
                }
            }
            .onEnded { _ in
                isDragging = false
                dragStartX = nil
            }
    }
}
