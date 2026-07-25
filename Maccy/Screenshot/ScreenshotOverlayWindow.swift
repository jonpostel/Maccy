import AppKit

/// Fullscreen, transparent, click-through-blocking window used as the
/// screenshot selection surface. Covers a single screen.
final class ScreenshotOverlayWindow: NSWindow {

    let overlayView: ScreenshotOverlayView

    init(screen: NSScreen) {
        let frame = screen.frame
        self.overlayView = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Appear above everything (including Maccy's own popup).
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        isMovableByWindowBackground = false

        // Hide from the Dock / window list.
        styleMask = .borderless

        contentView = overlayView
        overlayView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
        makeKey()
        overlayView.window?.makeFirstResponder(overlayView)
        // Push the crosshair cursor onto the stack so it takes effect
        // immediately, even before the mouse enters the overlay view.
        NSCursor.crosshair.push()
    }

    /// Dismiss the overlay and restore the previous cursor.
    func dismiss() {
        NSCursor.pop()
        orderOut(nil)
    }
}
