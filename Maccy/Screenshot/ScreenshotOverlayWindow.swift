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
            defer: false,
            screen: screen
        )

        // Appear above everything (including Maccy's own popup).
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
    }
}
