# Screenshot Shortcut Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global keyboard shortcut that triggers a WeChat-style drag-to-select screenshot, saving the result as PNG to the clipboard with a `Maccy-<timestamp>.png` title.

**Architecture:** All new code lives in a new `Maccy/Screenshot/` folder. A `ScreenshotCoordinator` registers a `KeyboardShortcuts.Name.screenshot` handler (only active when the user enables it in settings). On trigger, it shows a fullscreen transparent `NSWindow` overlay containing a custom `NSView` that handles mouse drag selection. On mouse-up, the selected screen region is captured via `CGWindowListCreateImage` (excluding the overlay window), written to the system pasteboard as PNG, and picked up by the existing `Clipboard` infrastructure. A pre-registered `onNewCopy` hook overrides the history item title to `Maccy-<timestamp>.png`.

**Tech Stack:** Swift 5, AppKit (NSWindow/NSView), KeyboardShortcuts (existing dependency), Defaults (existing dependency), Settings framework (existing dependency), CoreGraphics (`CGWindowListCreateImage`) for capture.

---

## File Structure

### New files (all in `Maccy/Screenshot/`)

| File | Responsibility |
|------|----------------|
| `ScreenshotConstants.swift` | Constants (colors, dimensions, filename format) + custom `NSPasteboard.PasteboardType.screenshot` |
| `ScreenshotOverlayView.swift` | `NSView` subclass handling mouse drag selection + drawing dim/selection/border/size label; ESC cancels |
| `ScreenshotOverlayWindow.swift` | Fullscreen transparent `NSWindow` (`.screenSaver` level, accepts mouse/key) hosting the overlay view |
| `ScreenshotCapture.swift` | Screen capture + crop using `CGWindowListCreateImage`; permission preflight via `CGPreflightScreenCaptureAccess` |
| `ScreenshotCoordinator.swift` | Singleton: registers shortcut keydown handler + `onNewCopy` title-override hook; owns overlay lifecycle; writes PNG to pasteboard |
| `ScreenshotSettingsPane.swift` | SwiftUI `Settings.Container` view with enable toggle + `KeyboardShortcuts.Recorder` for `.screenshot` |

### New localization files

| File | Responsibility |
|------|----------------|
| `Maccy/Settings/en.lproj/ScreenshotSettings.strings` | English strings |
| `Maccy/Settings/zh-Hans.lproj/ScreenshotSettings.strings` | Simplified Chinese strings |

### Modified existing files (minimal, surgical additions)

| File | Change |
|------|--------|
| `Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift` | +1 line: `static let screenshot = Self("screenshot")` (no default shortcut) |
| `Maccy/Extensions/Defaults.Keys+Names.swift` | +1 line: `static let screenshotEnabled = Key<Bool>("screenshotEnabled", default: false)` |
| `Maccy/Extensions/Settings.PaneIdentifier+Panes.swift` | +1 line: `static let screenshot = Self("screenshot")` |
| `Maccy/Observables/AppState.swift` | +1 `Settings.Pane(...)` block in `openPreferences()` to register the screenshot pane |
| `Maccy/AppDelegate.swift` | +1 line in `applicationWillFinishLaunching` to register the `ScreenshotCoordinator` hook before `Clipboard.shared.onNewCopy` |
| `Maccy.xcodeproj/project.pbxproj` | Register all new files (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase, PBXResourcesBuildPhase) |

---

## Task 1: Foundation — settings keys, shortcut name, pane identifier, pasteboard type

**Files:**
- Modify: `Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift`
- Modify: `Maccy/Extensions/Defaults.Keys+Names.swift`
- Modify: `Maccy/Extensions/Settings.PaneIdentifier+Panes.swift`

- [ ] **Step 1: Add `.screenshot` keyboard shortcut name (no default — user must set it)**

In `Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift`, append inside the extension:

```swift
static let screenshot = Self("screenshot")
```

- [ ] **Step 2: Add `screenshotEnabled` Defaults key (default `false`)**

In `Maccy/Extensions/Defaults.Keys+Names.swift`, append inside `extension Defaults.Keys`:

```swift
static let screenshotEnabled = Key<Bool>("screenshotEnabled", default: false)
```

- [ ] **Step 3: Add `.screenshot` Settings.PaneIdentifier**

In `Maccy/Extensions/Settings.PaneIdentifier+Panes.swift`, append inside the extension:

```swift
static let screenshot = Self("screenshot")
```

- [ ] **Step 4: Commit**

```bash
git add Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift Maccy/Extensions/Defaults.Keys+Names.swift Maccy/Extensions/Settings.PaneIdentifier+Panes.swift
git commit -m "feat(screenshot): add foundation keys, shortcut name, and pane identifier"
```

---

## Task 2: ScreenshotConstants.swift — constants and pasteboard type

**Files:**
- Create: `Maccy/Screenshot/ScreenshotConstants.swift`

- [ ] **Step 1: Create the constants file**

```swift
import AppKit.NSPasteboard
import Foundation

/// Constants and types for the screenshot feature.
enum ScreenshotConstants {
    /// Filename prefix, e.g. "Maccy-20260726143000.png".
    static let filenamePrefix = "Maccy"
    static let filenameDateFormat = "yyyyMMddHHmmss"
    static let fileExtension = "png"

    /// Overlay appearance.
    static let overlayDimAlpha: CGFloat = 0.3
    static let selectionBorderColor = NSColor(calibratedWhite: 0.0, alpha: 0.85)
    static let selectionBorderWidth: CGFloat = 1.0
    static let selectionHandleSize: CGFloat = 6.0

    /// Minimum selection size to accept (avoids accidental clicks).
    static let minSelectionSize: CGFloat = 5.0

    /// Size label appearance.
    static let sizeLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let sizeLabelTextColor = NSColor.white
    static let sizeLabelBackgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.75)
    static let sizeLabelPadding: CGFloat = 4.0
    static let sizeLabelOffset: CGFloat = 6.0

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
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotConstants.swift
git commit -m "feat(screenshot): add constants and custom pasteboard type"
```

---

## Task 3: ScreenshotOverlayView.swift — drag selection UI

**Files:**
- Create: `Maccy/Screenshot/ScreenshotOverlayView.swift`

- [ ] **Step 1: Create the overlay view**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotOverlayView.swift
git commit -m "feat(screenshot): add overlay view with drag selection and ESC cancel"
```

---

## Task 4: ScreenshotOverlayWindow.swift — fullscreen transparent window

**Files:**
- Create: `Maccy/Screenshot/ScreenshotOverlayWindow.swift`

- [ ] **Step 1: Create the overlay window**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotOverlayWindow.swift
git commit -m "feat(screenshot): add fullscreen transparent overlay window"
```

---

## Task 5: ScreenshotCapture.swift — screen capture + crop

**Files:**
- Create: `Maccy/Screenshot/ScreenshotCapture.swift`

- [ ] **Step 1: Create the capture helper**

```swift
import AppKit
import CoreGraphics

/// Captures a screen region using `CGWindowListCreateImage`, excluding a
/// given overlay window so it does not appear in the result.
enum ScreenshotCapture {

    /// Returns `true` if screen capture permission has been granted.
    static func hasPermission() -> Bool {
        if #available(macOS 15.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        // On macOS 14, CGPreflightScreenCaptureAccess exists too; fall back to a probe.
        return CGPreflightScreenCaptureAccess()
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

        // Scale to Retina: CGWindowListCreateImage returns a bitmap at the
        // backing resolution; wrap in NSImage at logical size.
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
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotCapture.swift
git commit -m "feat(screenshot): add screen capture helper using CGWindowListCreateImage"
```

---

## Task 6: ScreenshotCoordinator.swift — orchestrator

**Files:**
- Create: `Maccy/Screenshot/ScreenshotCoordinator.swift`

- [ ] **Step 1: Create the coordinator**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotCoordinator.swift
git commit -m "feat(screenshot): add coordinator with shortcut, overlay lifecycle, and title override"
```

---

## Task 7: ScreenshotSettingsPane.swift — settings UI

**Files:**
- Create: `Maccy/Screenshot/ScreenshotSettingsPane.swift`

- [ ] **Step 1: Create the settings pane**

```swift
import Defaults
import KeyboardShortcuts
import Settings
import SwiftUI

struct ScreenshotSettingsPane: View {
    @Default(.screenshotEnabled) private var screenshotEnabled

    var body: some View {
        Settings.Container(contentWidth: 450) {
            Settings.Section(bottomDivider: true) {
                Toggle(isOn: $screenshotEnabled) {
                    Text("EnableScreenshot", tableName: "ScreenshotSettings")
                }
                .help(Text("EnableScreenshotTooltip", tableName: "ScreenshotSettings"))

                Text("EnableScreenshotDescription", tableName: "ScreenshotSettings")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.gray)
                    .controlSize(.small)
            }

            Settings.Section(
                bottomDivider: true,
                label: { Text("ScreenshotShortcut", tableName: "ScreenshotSettings") }
            ) {
                KeyboardShortcuts.Recorder(for: .screenshot)
                    .help(Text("ScreenshotShortcutTooltip", tableName: "ScreenshotSettings"))
            }

            Settings.Section(title: "") {
                Text("ScreenshotUsage", tableName: "ScreenshotSettings")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.gray)
                    .controlSize(.small)
            }
        }
    }
}

#Preview {
    ScreenshotSettingsPane()
        .environment(\.locale, .init(identifier: "en"))
}
```

- [ ] **Step 2: Commit**

```bash
git add Maccy/Screenshot/ScreenshotSettingsPane.swift
git commit -m "feat(screenshot): add settings pane with enable toggle and shortcut recorder"
```

---

## Task 8: Localization strings

**Files:**
- Create: `Maccy/Settings/en.lproj/ScreenshotSettings.strings`
- Create: `Maccy/Settings/zh-Hans.lproj/ScreenshotSettings.strings`

- [ ] **Step 1: Create English strings**

`Maccy/Settings/en.lproj/ScreenshotSettings.strings`:

```
"Title" = "Screenshot";
"EnableScreenshot" = "Enable screenshot shortcut";
"EnableScreenshotTooltip" = "When enabled, pressing the configured shortcut starts a region screenshot.";
"EnableScreenshotDescription" = "Drag to select an area of the screen. The screenshot is copied to the clipboard as Maccy-<timestamp>.png.";
"ScreenshotShortcut" = "Shortcut:";
"ScreenshotShortcutTooltip" = "Global shortcut to start a screenshot. No default — you must set one.";
"ScreenshotUsage" = "Press the shortcut, drag to select, release to capture. Press Esc to cancel. Screen Recording permission is required.";
"ScreenCapturePermissionNeeded" = "Maccy needs Screen Recording permission to take screenshots. Please grant it in System Settings.";
```

- [ ] **Step 2: Create Simplified Chinese strings**

`Maccy/Settings/zh-Hans.lproj/ScreenshotSettings.strings`:

```
"Title" = "截图";
"EnableScreenshot" = "启用截图快捷键";
"EnableScreenshotTooltip" = "启用后，按下设置的快捷键即可开始区域截图。";
"EnableScreenshotDescription" = "拖动鼠标选择屏幕区域。截图将以 Maccy-<时间戳>.png 的名称复制到剪贴板。";
"ScreenshotShortcut" = "快捷键：";
"ScreenshotShortcutTooltip" = "启动截图的全局快捷键。无默认值，需自行设置。";
"ScreenshotUsage" = "按下快捷键，拖动选择区域，松开即可截图。按 Esc 取消。需要屏幕录制权限。";
"ScreenCapturePermissionNeeded" = "Maccy 需要屏幕录制权限才能截图。请在系统设置中授予。";
```

- [ ] **Step 3: Commit**

```bash
git add Maccy/Settings/en.lproj/ScreenshotSettings.strings Maccy/Settings/zh-Hans.lproj/ScreenshotSettings.strings
git commit -m "feat(screenshot): add en and zh-Hans localization strings"
```

---

## Task 9: Wire up — register coordinator and settings pane

**Files:**
- Modify: `Maccy/AppDelegate.swift`
- Modify: `Maccy/Observables/AppState.swift`

- [ ] **Step 1: Register the clipboard hook + shortcut in AppDelegate**

In `Maccy/AppDelegate.swift`, inside `applicationWillFinishLaunching(_:)`, add these two lines **before** `Clipboard.shared.onNewCopy { History.shared.add($0) }` (line 40):

```swift
ScreenshotCoordinator.shared.registerClipboardHook()
```

And add this line **after** the existing `Clipboard.shared.start()` call (line 41), still inside `applicationWillFinishLaunching`:

```swift
ScreenshotCoordinator.shared.registerShortcut()
```

The resulting block (lines 38–42 region) reads:

```swift
AppState.shared.appDelegate = self

ScreenshotCoordinator.shared.registerClipboardHook()
Clipboard.shared.onNewCopy { History.shared.add($0) }
Clipboard.shared.start()
ScreenshotCoordinator.shared.registerShortcut()
```

- [ ] **Step 2: Register the screenshot settings pane in AppState**

In `Maccy/Observables/AppState.swift`, inside `openPreferences()`, add a new `Settings.Pane(...)` entry to the `panes:` array. Insert it after the `general` pane and before the `storage` pane:

```swift
Settings.Pane(
  identifier: Settings.PaneIdentifier.screenshot,
  title: NSLocalizedString("Title", tableName: "ScreenshotSettings", comment: ""),
  toolbarIcon: NSImage.camera!
) {
  ScreenshotSettingsPane()
},
```

- [ ] **Step 3: Commit**

```bash
git add Maccy/AppDelegate.swift Maccy/Observables/AppState.swift
git commit -m "feat(screenshot): wire coordinator into AppDelegate and register settings pane"
```

---

## Task 10: Register new files in project.pbxproj

**Files:**
- Modify: `Maccy.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add PBXBuildFile entries** (one per Swift file + one per .strings file)

Follow the existing pattern. Generate unique 24-char hex IDs (e.g. `2FSCR000...`). Add to the `/* Begin PBXBuildFile section */`:

```
2FSCR0010000000000000001 /* ScreenshotConstants.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000001 /* ScreenshotConstants.swift */; };
2FSCR0010000000000000002 /* ScreenshotOverlayView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000002 /* ScreenshotOverlayView.swift */; };
2FSCR0010000000000000003 /* ScreenshotOverlayWindow.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000003 /* ScreenshotOverlayWindow.swift */; };
2FSCR0010000000000000004 /* ScreenshotCapture.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000004 /* ScreenshotCapture.swift */; };
2FSCR0010000000000000005 /* ScreenshotCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000005 /* ScreenshotCoordinator.swift */; };
2FSCR0010000000000000006 /* ScreenshotSettingsPane.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000006 /* ScreenshotSettingsPane.swift */; };
2FSCR0010000000000000007 /* ScreenshotSettings.strings in Resources */ = {isa = PBXBuildFile; fileRef = 2FSCR0020000000000000007 /* ScreenshotSettings.strings */; };
```

- [ ] **Step 2: Add PBXFileReference entries** in `/* Begin PBXFileReference section */`:

```
2FSCR0020000000000000001 /* ScreenshotConstants.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotConstants.swift; sourceTree = "<group>"; };
2FSCR0020000000000000002 /* ScreenshotOverlayView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotOverlayView.swift; sourceTree = "<group>"; };
2FSCR0020000000000000003 /* ScreenshotOverlayWindow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotOverlayWindow.swift; sourceTree = "<group>"; };
2FSCR0020000000000000004 /* ScreenshotCapture.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotCapture.swift; sourceTree = "<group>"; };
2FSCR0020000000000000005 /* ScreenshotCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotCoordinator.swift; sourceTree = "<group>"; };
2FSCR0020000000000000006 /* ScreenshotSettingsPane.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScreenshotSettingsPane.swift; sourceTree = "<group>"; };
2FSCR0020000000000000007 /* ScreenshotSettings.strings */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = ScreenshotSettings.strings; path = en.lproj/ScreenshotSettings.strings; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add a PBXGroup for `Screenshot/`** in the Maccy group (where `Extensions`, `Settings`, etc. live). Add the 6 Swift file refs + the `ScreenshotSettings.strings` ref as children. Also add the new group ref into the parent Maccy group's `children` array.

```
2FSCR0030000000000000001 /* Screenshot */ = {
  isa = PBXGroup;
  children = (
    2FSCR0020000000000000001 /* ScreenshotConstants.swift */,
    2FSCR0020000000000000002 /* ScreenshotOverlayView.swift */,
    2FSCR0020000000000000003 /* ScreenshotOverlayWindow.swift */,
    2FSCR0020000000000000004 /* ScreenshotCapture.swift */,
    2FSCR0020000000000000005 /* ScreenshotCoordinator.swift */,
    2FSCR0020000000000000006 /* ScreenshotSettingsPane.swift */,
  );
  path = Screenshot;
  sourceTree = "<group>";
};
```

- [ ] **Step 4: Add the 6 Swift files to the main target's PBXSourcesBuildPhase** (the `Sources` phase for the Maccy target, near line 1116 where `GeneralSettingsPane.swift in Sources` is listed):

```
2FSCR0010000000000000001 /* ScreenshotConstants.swift in Sources */,
2FSCR0010000000000000002 /* ScreenshotOverlayView.swift in Sources */,
2FSCR0010000000000000003 /* ScreenshotOverlayWindow.swift in Sources */,
2FSCR0010000000000000004 /* ScreenshotCapture.swift in Sources */,
2FSCR0010000000000000005 /* ScreenshotCoordinator.swift in Sources */,
2FSCR0010000000000000006 /* ScreenshotSettingsPane.swift in Sources */,
```

- [ ] **Step 5: Add the .strings file to the PBXResourcesBuildPhase** (the `Resources` phase, alongside the other `*.strings in Resources` entries):

```
2FSCR0010000000000000007 /* ScreenshotSettings.strings in Resources */,
```

- [ ] **Step 6: Build to verify**

```bash
xcodebuild -project Maccy.xcodeproj -scheme Maccy -configuration Debug build 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`. If there are signing errors unrelated to the new code, those are pre-existing and can be ignored for verification purposes.

- [ ] **Step 7: Commit**

```bash
git add Maccy.xcodeproj/project.pbxproj
git commit -m "build(screenshot): register screenshot files in project.pbxproj"
```

---

## Task 11: Manual verification

- [ ] **Step 1: Launch Maccy, open Preferences (⌘,), confirm a "Screenshot" tab appears.**

- [ ] **Step 2: Enable the toggle, record a shortcut (e.g. ⇧⌘S), confirm the shortcut is saved.**

- [ ] **Step 3: Press the shortcut — confirm a dim overlay covers the main screen with a crosshair cursor.**

- [ ] **Step 4: Drag a rectangle — confirm the selection area is bright, the rest is dim, and a size label follows the drag.**

- [ ] **Step 5: Release — confirm the overlay disappears and the screenshot appears at the top of Maccy's history with title `Maccy-<timestamp>.png`.**

- [ ] **Step 6: Paste (⌘V) into an image-capable app (e.g. Preview) — confirm the captured PNG is on the clipboard.**

- [ ] **Step 7: Press the shortcut, then ESC — confirm the overlay disappears with no screenshot saved.**

- [ ] **Step 8: Disable the toggle in settings — confirm the shortcut no longer triggers the overlay.**

---

## Self-Review Notes

**Spec coverage:**
- ✅ Shortcut-based screenshot trigger → Task 6 (coordinator) + Task 1 (shortcut name)
- ✅ Default off in settings → Task 1 (`screenshotEnabled` default `false`)
- ✅ User must enable + set shortcut → Task 7 (settings pane) + Task 6 (guard on `screenshotEnabled`)
- ✅ WeChat-style drag selection → Task 3 (overlay view) + Task 4 (overlay window)
- ✅ Save to clipboard by default → Task 6 (`saveToClipboard`)
- ✅ Filename `Maccy-<timestamp>.png` → Task 2 (`filename(for:)`) + Task 6 (title override hook)
- ✅ New code in separate folder → `Maccy/Screenshot/` (6 new files)
- ✅ Minimal source modifications → 5 existing files touched, 1–10 lines each
- ✅ Performance: overlay is a single NSWindow with lightweight `drawRect`; capture happens once on mouse-up; no per-frame screen grabs
- ✅ No extra features: no annotation, no save-to-disk, no multi-monitor (single main screen), no delay timer

**Type consistency:**
- `ScreenshotCoordinator.shared` used in AppDelegate (Task 9) and defined in Task 6 — match.
- `ScreenshotOverlayWindow.overlayView` accessed in Task 6 and defined in Task 4 — match.
- `ScreenshotOverlayView.onSelectionComplete` / `onSelectionCancel` closures used in Task 6 and defined in Task 3 — match.
- `ScreenshotCapture.capture(rect:excludingWindowID:)` signature used in Task 6 and defined in Task 5 — match.
- `NSPasteboard.PasteboardType.screenshot` defined in Task 2 and used in Task 6 — match.
- `KeyboardShortcuts.Name.screenshot` defined in Task 1 and used in Tasks 6 & 7 — match.
- `Defaults[.screenshotEnabled]` defined in Task 1 and used in Tasks 6 & 7 — match.

**Known limitations (documented, not bugs):**
- Single-monitor: only `NSScreen.main` is covered. Extending to all screens requires one overlay window per screen and is out of scope per "no extra features".
- `CGWindowListCreateImage` is deprecated in macOS 14 but still functional; `SCScreenshotManager` would require async flow and `SCShareableContent` authorization plumbing that adds complexity without user-visible benefit for a one-shot capture.
- Retina scaling: `CGWindowListCreateImage` with `.bestResolution` returns backing-pixel resolution; the NSImage is sized to the logical rect so displays correctly.
