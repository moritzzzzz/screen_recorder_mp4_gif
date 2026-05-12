import AppKit

class RegionSelectionView: NSView {
    var onSelectionComplete: ((NSRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw dark overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if let rect = selectionRect, rect.width > 1, rect.height > 1 {
            // Clear the selected region (punch a hole)
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            rect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            // Draw selection border
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2.0
            NSColor.white.setStroke()
            borderPath.setLineDash([6.0, 4.0], count: 2, phase: 0)
            borderPath.stroke()

            // Draw solid inner border
            let innerPath = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            innerPath.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.5).setStroke()
            innerPath.stroke()

            // Draw corner handles
            let handleSize: CGFloat = 8
            NSColor.white.setFill()
            let corners = [
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.maxX, y: rect.minY),
                NSPoint(x: rect.minX, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.maxY),
            ]
            for corner in corners {
                let handleRect = NSRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
            }

            // Draw dimensions label
            let width = Int(rect.width)
            let height = Int(rect.height)
            let dimensionText = "\(width) x \(height)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7),
            ]
            let textSize = dimensionText.size(withAttributes: attributes)
            let textRect = NSRect(
                x: rect.midX - textSize.width / 2,
                y: rect.minY - textSize.height - 8,
                width: textSize.width + 8,
                height: textSize.height + 4
            )
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
            dimensionText.draw(
                at: NSPoint(x: textRect.origin.x + 4, y: textRect.origin.y + 2),
                withAttributes: attributes
            )
        }

        // Draw instruction text at top
        let instruction = "Click and drag to select recording area. Press Escape to cancel." as NSString
        let instrAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let instrSize = instruction.size(withAttributes: instrAttributes)
        let bgRect = NSRect(
            x: bounds.midX - instrSize.width / 2 - 16,
            y: bounds.maxY - instrSize.height - 40,
            width: instrSize.width + 32,
            height: instrSize.height + 16
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8).fill()
        instruction.draw(
            at: NSPoint(x: bgRect.origin.x + 16, y: bgRect.origin.y + 8),
            withAttributes: instrAttributes
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        if let start = startPoint, let current = currentPoint {
            selectionRect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect = selectionRect, rect.width > 10, rect.height > 10 {
            onSelectionComplete?(rect)
        } else {
            // Selection too small — treat as cancel
            startPoint = nil
            currentPoint = nil
            selectionRect = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onSelectionCancelled?()
        }
    }
}
