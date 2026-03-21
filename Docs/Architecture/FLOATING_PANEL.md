# Floating Panel Pattern

> Reference for building resizable, draggable floating panels in Cider. Follow this pattern for any new floating surface (notes, scratchpad, mini-player, etc).

---

## Overview

Cider's floating panels combine three layers:

1. **NSPanel** — borderless, non-activating, custom shadow
2. **NSHostingView subclass** — bridges SwiftUI content into the panel
3. **SwiftUI view** — acrylic background + content + resize handle

The command palette is a fixed-size panel (no resize). This document covers the **resizable** variant, first used by the Notes panel.

### Fixed-Size Panel Variant

Fixed-size panels (e.g., toast panels) differ from resizable panels in a few key ways:

```swift
final class MyFixedPanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 500)
        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow

        isMovable = false                // Fixed position — not draggable
        acceptsMouseMovedEvents = true   // Needed for hover tracking
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

Key differences from resizable panels: `isMovable = false` (panel stays put), `acceptsMouseMovedEvents = true` (for hover tracking), and `.transient` in `collectionBehavior` (dismissed when switching spaces, unlike persistent panels).

---

## Panel (NSPanel subclass)

```swift
final class MyPanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 400, height: 520)

        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                    // We draw custom shadow
        isMovableByWindowBackground = true   // Drag from anywhere
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }   // Required for text input
    override var canBecomeMain: Bool { false }
}
```

**Key decisions:**

| Property | Value | Why |
|----------|-------|-----|
| `.borderless` | yes | No system chrome — we draw everything |
| `.nonactivatingPanel` | yes | Never steals focus from other apps |
| `hasShadow = false` | yes | We draw our own shadow as a blurred shape via `AcrylicPanelBackground` |
| `isMovableByWindowBackground` | `true` | Drag the panel from any non-interactive area |
| `collectionBehavior` | no `.transient` | Panel persists across spaces (unlike command palette which uses `.transient`) |
| `.resizable` | **omitted** | System resize handles don't work with shadow padding — we implement resize ourselves |

### Pin toggle (optional)

For panels that should optionally float above all windows:

```swift
func setPinned(_ pinned: Bool) {
    level = pinned ? .floating : .normal
}
```

### Show at mouse

Position near the cursor, clamped to screen visible frame:

```swift
func showAtMouse() {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
        ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }

    let screenFrame = screen.visibleFrame
    let panelSize = frame.size

    var x = mouseLocation.x - panelSize.width / 2
    var y = mouseLocation.y - panelSize.height / 2

    x = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
    y = max(screenFrame.minY, min(y, screenFrame.maxY - panelSize.height))

    setFrameOrigin(NSPoint(x: x, y: y))
    makeKeyAndOrderFront(nil)
}
```

---

## Hosting View (NSHostingView subclass)

```swift
final class MyPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true  // Click-through without requiring focus first
    }
}
```

---

## Shadow Padding (AppDelegate wiring)

The custom shadow (a blurred black shape inside `AcrylicPanelBackground`) needs space to render without clipping. The panel frame must be larger than the visible content.

```swift
private func updateMyPanelView() {
    guard let panel = myPanel, let viewModel = myViewModel else { return }

    let shadowPadding = MyDesign.shadowPadding  // 40pt
    let myView = MyPanelView(viewModel: viewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, shadowPadding)
        .padding(.top, 20)                       // Smaller top padding
        .padding(.bottom, shadowPadding + 15)    // Extra bottom for downward shadow

    let hostingView = MyPanelHostingView(rootView: myView)
    panel.contentView = hostingView

    // Initial panel size = content + padding
    let width = MyDesign.defaultWidth + shadowPadding * 2
    let height = MyDesign.defaultHeight + 20 + shadowPadding + 15
    panel.setContentSize(NSSize(width: width, height: height))
}
```

**Why external padding?** The blurred shadow shape extends ~36pt below and ~18pt to the sides of the visible content. Without padding, the window frame clips it. The padding gives the shadow room to render inside the window frame.

**Trade-off:** External padding means `.resizable` style mask won't work — the system's resize handles end up in the invisible padding area, unreachable by the user. That's why we implement custom resize (see below).

---

## View Structure

### CiderPanel Sidebar Column

The main CiderPanel uses a full-height sidebar column alongside the right content column:

```
HStack(spacing: 0) {
    sidebarColumn          // Full-height floating sidebar with header/footer
    VStack(spacing: 0) {   // Right column
        titleBar           // Animated sidebar toggle + tab bar + capture button
        Divider            // Inset horizontally
        contentArea        // Tab content
    }
}
```

The sidebar column wraps `sidebarHeader` (traffic lights + collapse toggle), `FolderSidebarView(showBackground: false)`, and `sidebarFooter` (gear + "New" pill menu + view options) in a single rounded-rect container with padding — creating a floating appearance over the acrylic background. Traffic lights disappear when sidebar is collapsed; right-click context menu on the title bar provides fallback window controls. When the sidebar closes, a toggle button appears in the title bar after a 150ms delay (bouncy spring); when the sidebar opens, the title bar toggle slides out immediately (snappy spring).

### Sidebar Compact Mode

When the panel width drops below `sidebarCompactThreshold` (680pt), the
sidebar auto-collapses to an overlay. When the panel widens past the
threshold again, the sidebar auto-reopens (if it was auto-collapsed, not
manually collapsed).

**Critical:** Measure the full panel width (HStack), NOT the content area
width. Content width changes when the sidebar toggles, creating a feedback
loop: collapse → content widens → threshold no longer met → expand →
content shrinks → threshold met → collapse → ∞. Panel width is stable
across sidebar state changes.

### Generic Panel View

```swift
struct MyPanelView: View {
    @ObservedObject var viewModel: MyViewModel

    var body: some View {
        ZStack {
            // Acrylic background with custom shadow + rounded corners + border
            AcrylicPanelBackground(cornerRadius: MyDesign.cornerRadius)

            VStack(spacing: 0) {
                // Title bar, content, status bar, etc.
            }
        }
        .overlay(alignment: .bottomTrailing) {
            MyResizeHandle()  // AppKit-based resize grip
        }
    }
}
```

`AcrylicPanelBackground` handles:
- Custom shadow (blurred black `RoundedRectangle`, offset down 18pt, opacity 0.7)
- Acrylic material (`VisualEffectView` + dark/highlight overlays)
- Rounded corners via `.clipShape()`
- Inner border stroke
- Accessibility fallback for Reduce Transparency

---

## Custom Resize Handle

This is the most critical pattern. We can't use system resize (`.resizable` style mask) because the shadow padding makes the window frame larger than the visible content.

### Why AppKit, not SwiftUI DragGesture?

SwiftUI's `DragGesture` reports coordinates in the view's local coordinate space. As the window resizes, the view's position changes, causing SwiftUI to recalculate the gesture — creating a feedback loop that makes the window bounce violently. **Always use AppKit mouse tracking for window resize.**

### Implementation

The resize handle is an `NSViewRepresentable` wrapping an `NSView` that runs its own event-tracking loop:

```swift
// SwiftUI wrapper
struct MyResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }
    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}
```

```swift
final class ResizeHandleNSView: NSView {
    private var trackingArea: NSTrackingArea?

    // CRITICAL: Prevents isMovableByWindowBackground from starting a
    // window drag when the user clicks the resize handle.
    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }
    override var isFlipped: Bool { false }

    // --- Tracking area for cursor changes ---

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.frameResize(position: .bottomRight,
                             directions: [.inward, .outward]).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    // --- Drawing ---

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(
            systemSymbolName: "arrow.down.backward.and.arrow.up.forward",
            accessibilityDescription: "Resize"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))

        if let symbol {
            let size = symbol.size
            let origin = NSPoint(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2)
            symbol.draw(at: origin, from: .zero,
                        operation: .sourceOver, fraction: 0.35)
        }
    }

    // --- Resize via event-tracking loop ---

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let initialFrame = window.frame
        let initialMouse = NSEvent.mouseLocation

        // Run our own event loop — same pattern as NSWindow.performDrag(with:).
        // This completely owns mouse tracking until mouseUp, preventing
        // interference from isMovableByWindowBackground or SwiftUI layout.
        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                // Account for shadow padding in minimum size
                let sp = MyDesign.shadowPadding
                let minW = MyDesign.minWidth + sp * 2
                let minH = MyDesign.minHeight + 20 + sp + 15

                let w = max(minW, initialFrame.width + dx)
                let h = max(minH, initialFrame.height - dy)
                // Anchor top-left: adjust origin.y as height changes
                let y = initialFrame.origin.y + (initialFrame.height - h)

                window.setFrame(
                    NSRect(x: initialFrame.origin.x, y: y, width: w, height: h),
                    display: true
                )

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }
}
```

### Key details

| Detail | Why |
|--------|-----|
| `mouseDownCanMoveWindow = false` | Checked by AppKit **before** `mouseDown` fires. Prevents `isMovableByWindowBackground` from starting a window drag on the resize handle. Without this, the window moves AND resizes simultaneously. |
| `window.nextEvent(matching:)` loop | Same pattern as `NSWindow.performDrag(with:)`. Takes over the run loop, so no other event handler (SwiftUI gestures, window drag) can interfere. |
| Screen coordinates (`NSEvent.mouseLocation`) | Stable reference frame. View-local coordinates shift as the window resizes, causing feedback loops. |
| Min size includes shadow padding | `minWidth + padding * 2` ensures the visible content never shrinks below its minimum. |
| Anchor top-left on resize | `origin.y` adjusts as height changes so the top edge stays fixed while the bottom edge moves. |

---

## Lessons Learned

### Rounded corners with VisualEffectView

`NSVisualEffectView` with `.behindWindow` blending is composited by the window server using the rectangular window frame. SwiftUI's `.clipShape()` doesn't affect the compositor — the blur bleeds past rounded corners.

**Solution:** External shadow padding makes the panel frame larger than the visible content. `AcrylicPanelBackground` clips the acrylic material to a `RoundedRectangle` inside the padding, so the rectangular window frame never cuts into the rounded corners.

### SwiftUI DragGesture + window resize = bounce

SwiftUI's `DragGesture` tracks position in view-local coordinates. Resizing the window moves the view, which recalculates the gesture, which triggers another resize — a feedback loop causing violent bouncing. **Always use AppKit `NSView.mouseDown` + `window.nextEvent` for window frame manipulation.**

### isMovableByWindowBackground + resize handle conflict

`isMovableByWindowBackground = true` checks `mouseDownCanMoveWindow` on the hit-tested view to decide whether to start a drag. If this returns `true` (the default), the window drag starts **before** the view's `mouseDown` fires. Setting `isMovableByWindowBackground = false` in `mouseDown` is too late. Override `mouseDownCanMoveWindow` to return `false` on the resize handle view instead.

### VisualEffectView blending in transparent windows

`.behindWindow` blending samples what's behind the *window* — the desktop wallpaper and other apps. Since our panels use `backgroundColor = .clear` (for custom shadow rendering), any `VisualEffectView(.behindWindow)` added to overlay views inside the panel will show wallpaper colors bleeding through, even though the panel's own acrylic is visually opaque underneath.

**Solution:** Use `.withinWindow` blending for overlay views (compact sidebar, detail sheets) that sit on top of the panel's own acrylic. This samples from the window's own rendered content — the dark acrylic — giving the correct dark frosted appearance without wallpaper bleed-through.

Only the panel's base `AcrylicPanelBackground` should use `.behindWindow`.

---

## Design Constants

Define in `Constants.swift`:

```swift
enum MyDesign {
    static let defaultWidth: CGFloat = 400
    static let defaultHeight: CGFloat = 520
    static let minWidth: CGFloat = 300
    static let minHeight: CGFloat = 300
    static let cornerRadius: CGFloat = Radius.lg   // 14pt
    static let shadowPadding: CGFloat = 40
    static let titleBarHeight: CGFloat = 40
}
```

---

## Checklist for new floating panels

1. Create `NSPanel` subclass — borderless, non-activating, no system shadow
2. Create `NSHostingView` subclass with `acceptsFirstMouse` override
3. Use `AcrylicPanelBackground` for acrylic + shadow + corners
4. Apply external shadow padding in AppDelegate wiring
5. Add AppKit-based resize handle with `mouseDownCanMoveWindow = false` and `nextEvent` loop
6. Add design constants to `Constants.swift`
7. Wire show/hide/toggle in AppDelegate with notification observers
8. Add hotkey detector if needed (follow `BookmarksHotkeyDetector` / `NotesHotkeyDetector` pattern)

### Companion Window Defaults (Notes/Bookmarks baseline)

Apply these defaults to any new companion window unless there is a strong reason not to:

1. Traffic lights use `NotesDesign` sizing/spacing tokens (no per-window variants).
2. Yellow traffic light collapses to a strip and restores without losing panel state.
3. Resizable bottom-right handle with consistent minimum size and clamp-to-screen behavior.
4. Respect `remember...PanelPosition` settings when opening/reopening.
5. Route global Ctrl+Option tiling hotkeys to the panel when it is focused or hovered.
6. Keep panel acrylic/chrome behavior consistent (`AcrylicPanelBackground`, custom shadow padding).

---

## File References

- `CiderPanel.swift` — Main NSPanel implementation (resizable, draggable, cross-monitor movement)
- `CiderPanelView.swift` — Main panel view with sidebar, tab bar, inline note editor, resize handles
- <!-- Removed: NotesPanel.swift / NotesPanelView.swift — standalone panels removed in Feb 2026 consolidation -->
- `AcrylicPanelBackground.swift` (`Views/Shared/`) — Shared acrylic + shadow background component
- `Docs/Design/ACRYLIC_IMPLEMENTATION.md` — Full shadow/border/material documentation
