import AppKit
import Defaults
import KeyboardShortcuts

/// Single entry point for the screenshot feature.
/// - Registers the `KeyboardShortcuts.Name.screenshot` handler (only active
///   when `Defaults[.screenshotEnabled]` is `true`).
/// - Registers a `Clipboard.onNewCopy` hook that overrides the history item
///   title for screenshots to `Maccy-<timestamp>.png`.
/// - Owns the overlay window lifecycle.
final class ScreenshotCoordinator {

    static let shared = ScreenshotCoordinator()

    private var overlayWindow: ScreenshotOverlayWindow?
    private var shortcutToken: KeyboardShortcuts.OnKeyDown?

    private init() {}

    // MARK: - Lifecycle

    /// Call once at app launch (before `Clipboard.shared.onNewCopy` is registered
    /// in `AppDelegate.applicationWillFinishLaunching`) so the title-override
    /// hook runs before `History.shared.add`.
    func registerClipboardHook() {
        Clipboard.shared.onNewCopy { [weak self] item in
            self?.overrideTitleIfNeeded(for: item)
        }
    }

    /// Call once at app launch to register the global shortcut handler.
    /// The handler checks `screenshotEnabled` at trigger time, so the
    /// shortcut can be recorded even while the feature is off.
    func registerShortcut() {
        shortcutToken = KeyboardShortcuts.onKeyDown(for: .screenshot) { [weak self] in
            self?.handleShortcut()
        }
    }

    // MARK: - Shortcut handling

    private func handleShortcut() {
        guard Defaults[.screenshotEnabled] else { return }
        guard overlayWindow == nil else { return } // already in progress

        if !ScreenshotCapture.hasPermission() {
            ScreenshotCapture.requestPermission()
            Notifier.notify(body: NSLocalizedString(
                "ScreenCapturePermissionNeeded",
                tableName: "ScreenshotSettings",
                comment: ""
            ), sound: nil)
            return
        }

        showOverlay()
    }

    // MARK: - Overlay

    private func showOverlay() {
        guard let screen = NSScreen.main else { return }

        let window = ScreenshotOverlayWindow(screen: screen)
        window.overlayView.onSelectionComplete = { [weak self, weak window] screenRect in
            guard let self, let window else { return }
            self.completeSelection(screenRect: screenRect, overlayWindow: window)
        }
        window.overlayView.onSelectionCancel = { [weak self, weak window] in
            guard let self, let window else { return }
            self.cancel(overlayWindow: window)
        }

        overlayWindow = window
        window.show()
    }

    private func completeSelection(screenRect: NSRect, overlayWindow window: ScreenshotOverlayWindow) {
        let windowID = CGWindowID(window.windowNumber)

        // Close the overlay first so it doesn't linger; we exclude it from
        // capture by window ID as well (belt-and-suspenders).
        closeOverlay()

        guard let image = ScreenshotCapture.capture(rect: screenRect, excludingWindowID: windowID) else {
            return
        }

        saveToClipboard(image: image)
    }

    private func cancel(overlayWindow window: ScreenshotOverlayWindow) {
        closeOverlay()
    }

    private func closeOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    // MARK: - Clipboard

    private func saveToClipboard(image: NSImage) {
        guard let pngData = ScreenshotCapture.pngData(for: image) else { return }

        let title = ScreenshotConstants.filename(for: Date())

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        // Carry the filename so the onNewCopy hook can override the title.
        pasteboard.setString(title, forType: .screenshot)

        // Trigger immediate detection instead of waiting for the timer.
        DispatchQueue.main.async {
            Clipboard.shared.checkForChangesInPasteboard()
        }
    }

    // MARK: - Title override hook

    private func overrideTitleIfNeeded(for item: HistoryItem) {
        // Detect the screenshot marker type in the item's contents.
        let isScreenshot = item.contents.contains { content in
            content.type == NSPasteboard.PasteboardType.screenshot.rawValue
        }
        guard isScreenshot else { return }

        // Recover the filename from the content data.
        if let content = item.contents.first(where: { $0.type == NSPasteboard.PasteboardType.screenshot.rawValue }),
           let data = content.value,
           let filename = String(data: data, encoding: .utf8) {
            item.title = filename
        }
    }
}
