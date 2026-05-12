import AppKit

struct CapturedRegion: Equatable {
    let rect: CGRect          // In screen-local coordinates (points, bottom-left origin)
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat
}

@MainActor
class RegionSelectionController {
    private var windows: [RegionSelectionWindow] = []

    func beginSelection() async -> CapturedRegion? {
        return await withCheckedContinuation { continuation in
            var resumed = false

            for screen in NSScreen.screens {
                let window = RegionSelectionWindow(screen: screen)
                let view = RegionSelectionView()
                view.frame = NSRect(origin: .zero, size: screen.frame.size)

                view.onSelectionComplete = { [weak self] viewRect in
                    guard !resumed else { return }
                    resumed = true

                    let displayID = self?.displayID(for: screen) ?? CGMainDisplayID()
                    let scaleFactor = screen.backingScaleFactor

                    // The rect is in NSScreen coordinates with this screen's origin
                    // We need display-local coordinates (relative to this screen's origin)
                    let localRect = NSRect(
                        x: viewRect.origin.x,
                        y: viewRect.origin.y,
                        width: viewRect.width,
                        height: viewRect.height
                    )

                    let region = CapturedRegion(
                        rect: localRect,
                        displayID: displayID,
                        scaleFactor: scaleFactor
                    )

                    self?.closeAllWindows()
                    continuation.resume(returning: region)
                }

                view.onSelectionCancelled = { [weak self] in
                    guard !resumed else { return }
                    resumed = true
                    self?.closeAllWindows()
                    continuation.resume(returning: nil)
                }

                window.contentView = view
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
                windows.append(window)
            }
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        return screenNumber as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    private func closeAllWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}
