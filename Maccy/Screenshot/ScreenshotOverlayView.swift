import AppKit

/// Fullscreen view that dims the screen, lets the user drag a selection
/// rectangle, and reports the selection (in screen coordinates) or cancellation.
final class ScreenshotOverlayView: NSView {

    /// Called with the selection rectangle in screen (global) coordinates.
    var onSelectionComplete: ((NSRect) -> Void)?

    /// Called when the user cancels (ESC or click without drag).
    var onSelectionCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let start = startPoint, let end = currentPoint else {
            onSelectionCancel?()
            return
        }
        isSelecting = false

        let selectionRect = normalizedRect(from: start, to: end)
        guard selectionRect.width >= ScreenshotConstants.minSelectionSize,
              selectionRect.height >= ScreenshotConstants.minSelectionSize else {
            // Treat as a click — cancel.
            onSelectionCancel?()
            return
        }

        // Convert view rect → window rect → screen rect.
        let windowRect = convert(selectionRect, to: nil)
        guard let screenRect = window?.convertToScreen(windowRect) else {
            onSelectionCancel?()
            return
        }
        onSelectionComplete?(screenRect)
    }

    // MARK: - Keyboard handling

    override func keyDown(with event: NSEvent) {
        // 53 = ESC
        if event.keyCode == 53 {
            onSelectionCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onSelectionCancel?()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Dim the entire screen.
        NSColor.black.withAlphaComponent(ScreenshotConstants.overlayDimAlpha).setFill()
        bounds.fill()

        guard isSelecting, let start = startPoint, let end = currentPoint else { return }

        let selection = normalizedRect(from: start, to: end)

        // Punch a hole: clear the selection so the underlying screen shows through.
        NSColor.clear.setFill()
        NSRect.fill(selection)

        // Selection border.
        ScreenshotConstants.selectionBorderColor.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = ScreenshotConstants.selectionBorderWidth
        path.stroke()

        // Size label.
        drawSizeLabel("\(Int(selection.width)) × \(Int(selection.height))", near: selection)
    }

    // MARK: - Helpers

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(a.x - b.x)
        let h = abs(a.y - b.y)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func drawSizeLabel(_ text: String, near rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: ScreenshotConstants.sizeLabelFont,
            .foregroundColor: ScreenshotConstants.sizeLabelTextColor
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()
        let padding = ScreenshotConstants.sizeLabelPadding
        let offset = ScreenshotConstants.sizeLabelOffset

        var labelRect = NSRect(
            x: rect.minX,
            y: rect.minY - size.height - offset,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        // If the label would fall below the selection, put it above.
        if labelRect.minY < bounds.minY {
            labelRect.origin.y = rect.maxY + offset
        }
        // Clamp horizontally.
        if labelRect.maxX > bounds.maxX {
            labelRect.origin.x = bounds.maxX - labelRect.width
        }

        ScreenshotConstants.sizeLabelBackgroundColor.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()

        let textOrigin = NSPoint(
            x: labelRect.minX + padding,
            y: labelRect.minY + (labelRect.height - size.height) / 2
        )
        attrString.draw(at: textOrigin)
    }
}
