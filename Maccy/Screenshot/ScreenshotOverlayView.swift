import AppKit

/// Fullscreen overlay for screenshot selection.
///
/// Interaction model:
/// - Mouse moves → highlight the window under the cursor.
/// - Single click → capture the highlighted window.
/// - Drag → free-form rectangular selection.
/// - Double click → capture the entire screen.
/// - Right click or ESC → cancel.
/// - Return → capture the highlighted window.
final class ScreenshotOverlayView: NSView {

    /// Called with the selection rectangle in screen (global) coordinates.
    var onSelectionComplete: ((NSRect) -> Void)?

    /// Called with the CGWindowID of the window to capture.
    var onWindowCapture: ((CGWindowID) -> Void)?

    /// Called to capture the entire screen.
    var onFullScreenCapture: (() -> Void)?

    /// Called when the user cancels (ESC, right click, or click without drag).
    var onSelectionCancel: (() -> Void)?

    // MARK: - State

    private var dragStartPoint: NSPoint?
    private var currentDragPoint: NSPoint?
    private var isDragging = false

    private var highlightedWindowID: CGWindowID?
    private var highlightedWindowRect: NSRect?

    private var pendingSingleClick: DispatchWorkItem?

    private let dragThreshold: CGFloat = 5.0
    private let doubleClickDelay: TimeInterval = 0.25

    /// The overlay window's own CGWindowID, used to exclude it from window detection.
    var overlayWindowID: CGWindowID = 0

    // MARK: - Setup

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas and add a fresh one covering the full bounds
        // so mouseMoved fires even without holding a button.
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Mouse tracking

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        updateHighlightedWindow(at: viewPoint)
    }

    override func mouseDown(with event: NSEvent) {
        // Cancel any pending single-click from a previous click.
        pendingSingleClick?.cancel()
        pendingSingleClick = nil

        let viewPoint = convert(event.locationInWindow, from: nil)
        dragStartPoint = viewPoint
        currentDragPoint = viewPoint
        isDragging = false

        // Clear window highlight when starting a potential drag.
        highlightedWindowID = nil
        highlightedWindowRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        currentDragPoint = viewPoint

        // Once the mouse moves beyond the drag threshold, enter selection mode.
        if !isDragging {
            let dx = viewPoint.x - startPoint.x
            let dy = viewPoint.y - startPoint.y
            if hypot(dx, dy) > dragThreshold {
                isDragging = true
            }
        }

        if isDragging {
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Double click → capture full screen.
        if event.clickCount >= 2 {
            onFullScreenCapture?()
            return
        }

        // Drag selection → capture the selected rect.
        if isDragging, let start = dragStartPoint, let end = currentDragPoint {
            isDragging = false
            let selectionRect = normalizedRect(from: start, to: end)
            guard selectionRect.width >= ScreenshotConstants.minSelectionSize,
                  selectionRect.height >= ScreenshotConstants.minSelectionSize else {
                onSelectionCancel?()
                return
            }

            let windowRect = convert(selectionRect, to: nil)
            guard let screenRect = window?.convertToScreen(windowRect) else {
                onSelectionCancel?()
                return
            }
            onSelectionComplete?(screenRect)
            return
        }

        // Single click → capture the highlighted window (after a short delay
        // to allow a potential double-click to take precedence).
        if let windowID = highlightedWindowID {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.onWindowCapture?(windowID)
            }
            pendingSingleClick = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleClickDelay, execute: workItem)
        } else {
            // No window highlighted — cancel.
            onSelectionCancel?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSelectionCancel?()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            onSelectionCancel?()
        case 36: // Return
            if let windowID = highlightedWindowID {
                onWindowCapture?(windowID)
            } else {
                onFullScreenCapture?()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onSelectionCancel?()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Window detection

    private func updateHighlightedWindow(at viewPoint: NSPoint) {
        // Convert view point → window point → screen point → CG screen point.
        let windowPoint = convert(viewPoint, to: nil)
        guard let screenPoint = window?.convertToScreen(windowPoint) else { return }
        guard let screenHeight = window?.screen?.frame.height else { return }

        // CG uses top-left origin; NS uses bottom-left.
        let cgPoint = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)

        if let result = ScreenshotCapture.windowAtPoint(cgPoint, excludingWindowID: overlayWindowID) {
            if highlightedWindowID != result.windowID {
                highlightedWindowID = result.windowID
                highlightedWindowRect = convertCGRectToView(result.rect)
                needsDisplay = true
            }
        } else if highlightedWindowID != nil {
            highlightedWindowID = nil
            highlightedWindowRect = nil
            needsDisplay = true
        }
    }

    /// Converts a CGRect in CG screen coordinates to this view's coordinate space.
    private func convertCGRectToView(_ cgRect: CGRect) -> NSRect {
        guard let screen = window?.screen else { return .zero }
        let screenHeight = screen.frame.height

        // CG rect: origin top-left, y down.
        // NS screen rect: origin bottom-left, y up.
        let nsScreenY = screenHeight - cgRect.origin.y - cgRect.height
        let screenRect = NSRect(
            x: cgRect.origin.x + screen.frame.origin.x,
            y: nsScreenY + screen.frame.origin.y,
            width: cgRect.width,
            height: cgRect.height
        )

        // Convert screen rect → window rect → view rect.
        let windowRect = window?.convertFromScreen(screenRect) ?? screenRect
        return convert(windowRect, from: nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Dim the entire screen.
        NSColor.black.withAlphaComponent(ScreenshotConstants.overlayDimAlpha).setFill()
        bounds.fill()

        // Draw the highlighted window (if any and not dragging).
        if !isDragging, let highlightRect = highlightedWindowRect {
            // Clear the highlighted window area.
            NSColor.clear.setFill()
            highlightRect.fill()

            // Draw a bright border around the highlighted window.
            ScreenshotConstants.selectionBorderColor.setStroke()
            let path = NSBezierPath(rect: highlightRect)
            path.lineWidth = ScreenshotConstants.selectionBorderWidth
            path.stroke()

            drawCornerHandles(for: highlightRect)
        }

        // Draw the drag selection (if dragging).
        if isDragging, let start = dragStartPoint, let end = currentDragPoint {
            let selection = normalizedRect(from: start, to: end)

            NSColor.clear.setFill()
            selection.fill()

            ScreenshotConstants.selectionBorderColor.setStroke()
            let path = NSBezierPath(rect: selection)
            path.lineWidth = ScreenshotConstants.selectionBorderWidth
            path.stroke()

            drawCornerHandles(for: selection)
            drawSizeLabel("\(Int(selection.width)) × \(Int(selection.height))", near: selection)
        }
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

        // Top-left
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - length))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + length, y: rect.maxY))

        // Top-right
        path.move(to: NSPoint(x: rect.maxX - length, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - length))

        // Bottom-right
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY + length))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - length, y: rect.minY))

        // Bottom-left
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

        var labelRect = NSRect(
            x: rect.maxX + offset,
            y: rect.maxY + offset,
            width: size.width + padding * 2,
            height: size.height + padding
        )

        if labelRect.maxX > bounds.maxX {
            labelRect.origin.x = rect.maxX - labelRect.width - offset
        }
        if labelRect.maxY > bounds.maxY {
            labelRect.origin.y = rect.minY - labelRect.height - offset
        }
        if labelRect.minX < bounds.minX {
            labelRect.origin.x = bounds.minX + offset
        }
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
