import AppKit
import CoreGraphics

/// Captures screen regions, windows, or full screens using CoreGraphics.
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

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: screenRect.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Captures a specific window by its CGWindowID.
    static func capture(windowID: CGWindowID) -> NSImage? {
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .nominalResolution, .boundsIgnoreFraming]
        )

        guard let cgImage else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: NSSize(width: cgImage.width, height: cgImage.height))
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Captures the entire main screen (all visible windows).
    static func captureScreen() -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let cgRect = CGRect(origin: .zero, size: screen.frame.size)

        let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        )

        guard let cgImage else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let image = NSImage(size: screen.frame.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Returns the window ID and bounds (in CG screen coordinates) of the
    /// topmost window at the given point, excluding the overlay window.
    static func windowAtPoint(_ cgPoint: CGPoint, excludingWindowID overlayID: CGWindowID) -> (windowID: CGWindowID, rect: CGRect)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElement],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for windowInfo in windowList {
            guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  windowID != overlayID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName != "Maccy"
            else { continue }

            let rect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            if rect.contains(cgPoint) {
                return (windowID, rect)
            }
        }
        return nil
    }

    /// Encodes an NSImage to PNG data.
    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
