import AppKit
import CoreGraphics

/// Captures a screen region using `CGWindowListCreateImage`, excluding a
/// given overlay window so it does not appear in the result.
enum ScreenshotCapture {

    /// Returns `true` if screen capture permission has been granted.
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts the user for screen capture permission (opens System Settings).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the given screen rect, excluding `excludeWindowID`.
    /// Returns an `NSImage` (PNG-representable) or `nil` on failure.
    static func capture(rect screenRect: NSRect, excludingWindowID excludeWindowID: CGWindowID) -> NSImage? {
        // CGWindowListCreateImage expects a rect in global display coordinates
        // (origin at top-left of the primary display). NSRect/NSWindow use a
        // bottom-left origin, so flip the Y.
        guard let screen = NSScreen.screens.first else { return nil }
        let screenHeight = screen.frame.height
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: screenHeight - screenRect.origin.y - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )

        let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            excludeWindowID,
            [.bestResolution, .nominalResolution]
        )

        guard let cgImage else { return nil }

        // CGWindowListCreateImage returns a bitmap at the backing resolution;
        // wrap in NSImage at logical size so it displays/saves correctly.
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: screenRect.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Encodes an NSImage to PNG data.
    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
