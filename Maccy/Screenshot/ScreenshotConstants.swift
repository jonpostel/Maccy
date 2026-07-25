import AppKit.NSPasteboard
import Foundation

/// Constants and types for the screenshot feature.
enum ScreenshotConstants {
    /// Filename prefix, e.g. "Maccy-20260726143000.png".
    static let filenamePrefix = "Maccy"
    static let filenameDateFormat = "yyyyMMddHHmmss"
    static let fileExtension = "png"

    /// Overlay appearance.
    static let overlayDimAlpha: CGFloat = 0.55
    static let selectionBorderColor = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
    static let selectionBorderWidth: CGFloat = 2.0
    static let selectionHandleSize: CGFloat = 6.0
    static let cornerHandleLength: CGFloat = 14.0
    static let cornerHandleWidth: CGFloat = 3.0
    static let crosshairLineColor = NSColor(white: 1.0, alpha: 0.35)
    static let crosshairLineWidth: CGFloat = 1.0

    /// Minimum selection size to accept (avoids accidental clicks).
    static let minSelectionSize: CGFloat = 5.0

    /// Size label appearance.
    static let sizeLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let sizeLabelTextColor = NSColor.white
    static let sizeLabelBackgroundColor = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.95)
    static let sizeLabelPadding: CGFloat = 6.0
    static let sizeLabelOffset: CGFloat = 8.0

    /// Builds the screenshot title, e.g. "Maccy-20260726143000.png".
    static func filename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = filenameDateFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "\(filenamePrefix)-\(formatter.string(from: date)).\(fileExtension)"
    }
}

/// Custom pasteboard type carrying the screenshot filename so the
/// `onNewCopy` hook can override the history item title.
extension NSPasteboard.PasteboardType {
    static let screenshot = NSPasteboard.PasteboardType(rawValue: "org.p0deje.Maccy.screenshot")
}
