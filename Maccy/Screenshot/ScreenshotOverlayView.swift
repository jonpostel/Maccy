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

    /// Allow the first mouse-down to be received without an extra click to
    /// activate the window. This makes the drag-to-select work immediately.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        // 1. Dim the entire screen with a darker mask for stronger contrast.
        NSColor.black.withAlphaComponent(ScreenshotConstants.overlayDimAlpha).setFill()
        bounds.fill()

        guard isSelecting, let start = startPoint, let end = currentPoint else { return }

        let selection = normalizedRect(from: start, to: end)

        // 2. Punch a hole: clear the selection so the underlying screen shows through.
        NSColor.clear.setFill()
        selection.fill()

        // 3. Selection border (bright blue).
        ScreenshotConstants.selectionBorderColor.setStroke()
        let borderPath = NSBezierPath(rect: selection)
        borderPath.lineWidth = ScreenshotConstants.selectionBorderWidth
        borderPath.stroke()

        // 4. Corner handles (L-shaped marks at each corner).
        drawCornerHandles(for: selection)

        // 5. Size label.
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

    private func drawCornerHandles(for rect: NSRect) {
        let length = ScreenshotConstants.cornerHandleLength
        let width = ScreenshotConstants.cornerHandleWidth
        let color = ScreenshotConstants.selectionBorderColor

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round

        // Top-left corner (L shape).
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - length))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + length, y: rect.maxY))

        // Top-right corner.
        path.move(to: NSPoint(x: rect.maxX - length, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - length))

        // Bottom-right corner.
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY + length))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - length, y: rect.minY))

        // Bottom-left corner.
        path.move(to: NSPoint(x: rect.minX + length, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + length))

        path.stroke()
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

        // Place the label just outside the bottom-right corner of the selection.
        var labelRect = NSRect(
            x: rect.maxX + offset,
            y: rect.maxY + offset,
            width: size.width + padding * 2,
            height: size.height + padding
        )

        // If the label would overflow the right edge, place it inside the selection.
        if labelRect.maxX > bounds.maxX {
            labelRect.origin.x = rect.maxX - labelRect.width - offset
        }
        // If the label would overflow the top edge, place it below the selection.
        if labelRect.maxY > bounds.maxY {
            labelRect.origin.y = rect.minY - labelRect.height - offset
        }
        // Clamp horizontally.
        if labelRect.minX < bounds.minX {
            labelRect.origin.x = bounds.minX + offset
        }
        // Clamp vertically.
        if labelRect.minY < bounds.minY {
            labelRect.origin.y = bounds.minY + offset
        }

        ScreenshotConstants.sizeLabelBackgroundColor.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()

        let textOrigin = NSPoint(
            x: labelRect.minX + padding,
            y: labelRect.minY + (labelRect.height - size.height) / 2
        )
        attrString.draw(at: textOrigin)
    }
}
