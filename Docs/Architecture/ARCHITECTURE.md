# Cider Architecture

> Consolidated reference for Cider's panel architecture, tech stack, and SwiftUI/AppKit integration patterns. Read this when working on panel layout, display modes, search, settings, floating panel surfaces, or debugging layout/focus/popover/drag-drop/keyboard issues.

---

## Table of Contents

- [Tech Stack](#tech-stack)
  - [Overview](#overview)
  - [Swift 6.2 Language](#swift-62-language)
  - [State Management Patterns](#state-management-patterns)
  - [Storage and Persistence](#storage-and-persistence)
  - [SwiftUI Patterns](#swiftui-patterns)
  - [AppKit Integration](#appkit-integration)
  - [Testing Patterns](#testing-patterns)
  - [Performance Checklist](#performance-checklist)
- [Floating Panel Pattern](#floating-panel-pattern)
  - [Panel (NSPanel subclass)](#panel-nspanel-subclass)
  - [Hosting View](#hosting-view-nshostingview-subclass)
  - [Shadow Padding](#shadow-padding-appdelegate-wiring)
  - [View Structure](#view-structure)
  - [Custom Resize Handle](#custom-resize-handle)
  - [Design Constants](#design-constants)
  - [Checklist for New Floating Panels](#checklist-for-new-floating-panels)
  - [Floating Panel Lessons Learned](#floating-panel-lessons-learned)
- [Panel Integration](#panel-integration)
  - [Panel Structure](#panel-structure)
  - [Panel Layout Alignment Rules](#panel-layout-alignment-rules)
  - [Bookmark Display Modes](#bookmark-display-modes)
  - [Note Display Modes](#note-display-modes)
  - [Home Display Modes](#home-display-modes)
  - [Search Architecture](#search-architecture)
  - [Settings Architecture](#settings-architecture)
  - [Cider Web Sync](#cider-web-sync)
- [SwiftUI + NSPanel Gotchas](#swiftui--nspanel-gotchas)
  - [Layout & Clipping](#layout--clipping)
  - [Context Menus](#context-menus)
  - [Focus & Keyboard](#focus--keyboard)
  - [Popovers](#popovers)
  - [Drag & Drop](#drag--drop)
  - [Mouse Events & NSViewRepresentable](#mouse-events--nsviewrepresentable)
  - [View Lifecycle & Data](#view-lifecycle--data)
  - [Card & Container Contracts](#card--container-contracts)
  - [AppKit Integration Gotchas](#appkit-integration-gotchas)
  - [Caching & Performance](#caching--performance)
  - [Build & Project](#build--project)
  - [Storage & Data Integrity](#storage--data-integrity)
  - [NSView / AppKit Deep](#nsview--appkit-deep)
- [File References](#file-references)

---

# Tech Stack

> **Read this for tech stack context.** This section covers Swift 6.2, SwiftUI, Combine, AppKit integration, and framework-specific patterns used in Cider.

## Overview

Cider uses a modern, native macOS tech stack:

| Layer | Technology | Version | Why |
|-------|-----------|---------|-----|
| Language | Swift | 6.2+ | Data-race safety, modern concurrency |
| UI Framework | SwiftUI | macOS 26+ | Declarative, performant, native |
| System Integration | AppKit | macOS 26+ | NSPanel, window management, system APIs |
| Concurrency | Swift Concurrency | 6.2+ | Async/await, actors, structured concurrency |
| Reactive State | Combine | macOS 26+ | @Published properties, reactive ViewModels |
| Storage | UserDefaults + JSON | macOS 26+ | Simple config persistence via Codable |
| Build System | Swift Package Manager | 6.2+ | SPM for dependencies + compilation; Xcode project wraps SPM for code signing |
| Auto-Updates | Sparkle | 2.6+ | macOS update framework |
| Sync | convex-swift | 0.8+ | Convex backend client |
| Local AI | mlx-swift-lm | 2.29.x | Apple MLX inference (Qwen 2.5) |
| YAML Parsing | Yams | 5.1+ | Kanban board YAML serialization |

Four external dependencies via SPM. All are well-maintained, permissively licensed libraries.

---

## Swift 6.2 Language

### Language Mode

Cider uses **Swift 6.2 language mode** with Swift Package Manager:

```swift
// Package.swift
// swift-tools-version: 6.2
let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm/", .upToNextMinor(from: "2.29.1")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    ],
    targets: [
        .target(
            name: "Cider",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ConvexMobile", package: "convex-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Cider"
        )
    ]
)
```

### Concurrency Model

Most code runs on the main actor by default. ViewModels and services use `@MainActor`:

```swift
// Standard ViewModel pattern used throughout Cider
@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var displayMode: BookmarkDisplayMode
    @Published var isVisible = false

    private var cancellables = Set<AnyCancellable>()
}

// Opt into background execution when needed
nonisolated func heavyComputation() async -> Result {
    return performWork()
}
```

#### When to Use Each Pattern

| Pattern | When to Use |
|---------|-------------|
| **@MainActor** (default) | UI updates, ViewModels, most app code |
| **nonisolated** | CPU-intensive work, I/O operations |
| **Actor** | Shared mutable state accessed from multiple contexts |
| **@Sendable closures** | Crossing actor boundaries safely |

### Sendable and Thread Safety

```swift
// Value types are implicitly Sendable
struct Bookmark: Sendable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
}

// Use OSAllocatedUnfairLock for lightweight thread safety
// (Used in DoubleTapDetector for suppressUntilNextOptionDown)
import os
let lock = OSAllocatedUnfairLock(initialState: false)
lock.withLock { state in
    state = true
}
```

### Typed Throws (New in Swift 6)

```swift
// Type-safe error handling
enum StorageError: Error {
    case encodingFailed
    case decodingFailed
    case permissionDenied
}

func saveConfig(_ config: CiderConfig) throws(StorageError) {
    guard let data = try? JSONEncoder().encode(config) else {
        throw .encodingFailed
    }
    UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
}
```

---

## State Management Patterns

### ObservableObject + @Published (Primary Pattern)

Cider uses `ObservableObject` with `@Published` properties for all ViewModels. **Not** `@Observable`.

```swift
// Standard ViewModel pattern used throughout Cider
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItemV2] = []
    @Published private(set) var recentItems: [LibraryItemV2] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to storage changes via Combine
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        rebuildItems()
    }

    func rebuildItems() {
        // Merge all storage types into unified feed
        // Pre-compute recentItems (top 8 by updatedDate)
        // ...
    }
}

// Dependency injection
struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel

    var body: some View {
        // ...
    }
}
```

**Why not `@Observable`?** Cider was built with `ObservableObject` + `@Published`, which works well with Combine subscriptions for reactive data flow between ViewModels.

### Combine for Reactive State

Cider uses **Combine extensively** for reactive state management:

```swift
// Data flows from services -> ViewModels -> Views via Combine subscriptions
@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
```

### When to Use Each

| Use Case | Pattern Used in Cider |
|----------|----------------------|
| ViewModel state | Combine (@Published) |
| View -> ViewModel binding | Combine (@ObservedObject, @Published) |
| Service -> ViewModel sync | Combine (.sink, .receive(on:)) |
| One-shot operations | async/await (Task, await) |
| Browser capture (AXUIElement) | Synchronous (AX APIs are sync) |
| Timer-based updates | Timer + @Published |
| Config change notifications | NotificationCenter + Combine |

---

## Storage and Persistence

Cider uses **UserDefaults + Codable** for all persistence. No database.

### CiderConfig Pattern

```swift
struct CiderConfig: Codable {
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var activationSpeed: Double
    var vaultDirectory: String
    var rememberPanelPosition: Bool
    var bookmarksDefaultViewMode: BookmarkDisplayMode
    // ... 40+ properties (see Models/CiderConfig.swift)

    static let storageKey = "CiderConfig"

    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(CiderConfig.self, from: data)
        } catch {
            NSLog("[Cider] Config decode error: \(error). Resetting to defaults.")
            UserDefaults.standard.removeObject(forKey: storageKey)
            let defaults = CiderConfig.default
            defaults.save()
            return defaults
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
        }
    }

    // Custom decoding -- every property uses decodeIfPresent + fallback
    // for backward compatibility when new fields are added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        // ... all properties follow this pattern
    }
}
```

### Content Storage

All user content is stored as standard files in `~/CiderVault/` (see `Docs/Architecture/STORAGE.md` for full details):
- Bookmarks: `.webloc` files + per-folder `.cider-meta.json` sidecar
- Notes: `.md` files
- Contacts: `.vcf` files
- Date Cards / Todos: `.ics` files
- App metadata: JSON indexes in `~/CiderVault/.cider/{type}/`
- App config: `CiderConfig` struct in UserDefaults (key: `"CiderConfig"`)

**Why not a database?**
- Files are the source of truth -- users can browse in Finder
- Standard formats (`.webloc`, `.md`, `.vcf`, `.ics`) open in native apps
- Simple read/write with Codable indexes for fast startup
- Atomic updates with `.atomic` write options

---

## SwiftUI Patterns

### Performance Fundamentals

**Core principle**: Keep view bodies lightweight and pure.

```swift
// Bad: Heavy computation in body
struct WindowRow: View {
    let window: WindowInfo

    var body: some View {
        HStack {
            Text(formatTitle(window.title))  // Bad: every render
        }
    }
}

// Good: Precomputed data
struct WindowRow: View {
    let window: WindowInfo
    let formattedTitle: String

    var body: some View {
        HStack {
            Text(formattedTitle)
        }
    }
}
```

### List Performance

```swift
// Use LazyVStack for custom layouts (Cider's primary pattern)
ScrollView {
    LazyVStack(spacing: Spacing.md) {
        ForEach(items) { item in
            CustomCard(item: item)
        }
    }
}

// Use explicit .id() for reorderable items
ForEach(pinnedApps) { app in
    AppIcon(app: app)
        .id(app.bundleID)
}
```

### Animation Best Practices

```swift
// Use SwiftUI spring presets (aliased in CiderAnimation)
withAnimation(.snappy) {
    isExpanded.toggle()
}

// Spring presets from CiderAnimation
withAnimation(CiderAnimation.snappy) {
    isExpanded.toggle()
}

// Respect Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .snappy) {
    isExpanded.toggle()
}
```

---

## AppKit Integration

> NSPanel setup patterns are documented in the [Floating Panel Pattern](#floating-panel-pattern) section below.

### NSPanel Integration

Key types:
- `CiderPanel` -- main resizable panel (`App/CiderPanel.swift`)
- `CiderPanelShell` -- SwiftUI shell with sidebar, resize, compact mode (`Views/Shared/CiderPanelShell.swift`)
- `AcrylicPanelBackground` -- acrylic + shadow + corners (`Views/Shared/AcrylicPanelBackground.swift`)
- `PanelEdgeResizeView` -- all-edge AppKit resize handles (`Views/Shared/PanelEdgeResizeView.swift`)

---

## Testing Patterns

### Swift Testing Framework

```swift
import Testing

@Test("Config loads with defaults for missing fields")
func configLoadsDefaults() throws {
    let oldJSON = """
    {"textSize":"medium"}
    """
    UserDefaults.standard.set(oldJSON.data(using: .utf8), forKey: "CiderConfig")

    let config = CiderConfig.load()

    #expect(config.showMenuBarIcon == true)
    #expect(config.activationMode == .doubleTap)
    #expect(config.textSize == .medium)
}
```

---

## Performance Checklist

When implementing any feature, verify:

- [ ] SwiftUI views use stable `.id()` for items
- [ ] Heavy computations moved out of view bodies
- [ ] @Published properties don't update too frequently
- [ ] Animations respect Reduce Motion
- [ ] No force unwrapping in production code
- [ ] Memory leaks checked (weak self in closures)
- [ ] Use spring animations, not linear/easeInOut

---

## Resources

### Official Documentation
- [Swift.org - Swift 6 Language Guide](https://docs.swift.org/swift-book/)
- [Apple - SwiftUI Performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)

### WWDC Sessions
- WWDC 2025: Optimize SwiftUI performance with Instruments
- WWDC 2024: What's new in Swift 6

---

# Floating Panel Pattern

> Reference for building resizable, draggable floating panels in Cider. Follow this pattern for any new floating surface (notes, scratchpad, mini-player, etc).

---

## Panel Overview

Cider's floating panels combine three layers:

1. **NSPanel** -- borderless, non-activating, custom shadow
2. **NSHostingView subclass** -- bridges SwiftUI content into the panel
3. **SwiftUI view** -- acrylic background + content + resize handle

The command palette is a fixed-size panel (no resize). This section covers the **resizable** variant, first used by the Notes panel.

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

        isMovable = false                // Fixed position -- not draggable
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
| `.borderless` | yes | No system chrome -- we draw everything |
| `.nonactivatingPanel` | yes | Never steals focus from other apps |
| `hasShadow = false` | yes | We draw our own shadow as a blurred shape via `AcrylicPanelBackground` |
| `isMovableByWindowBackground` | `true` | Drag the panel from any non-interactive area |
| `collectionBehavior` | no `.transient` | Panel persists across spaces (unlike command palette which uses `.transient`) |
| `.resizable` | **omitted** | System resize handles don't work with shadow padding -- we implement resize ourselves |

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

**Trade-off:** External padding means `.resizable` style mask won't work -- the system's resize handles end up in the invisible padding area, unreachable by the user. That's why we implement custom resize (see below).

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

The sidebar column wraps `sidebarHeader` (traffic lights + collapse toggle), `FolderSidebarView(showBackground: false)`, and `sidebarFooter` (gear + "New" pill menu + view options) in a single rounded-rect container with padding -- creating a floating appearance over the acrylic background. Traffic lights disappear when sidebar is collapsed; right-click context menu on the title bar provides fallback window controls. When the sidebar closes, a toggle button appears in the title bar after a 150ms delay (bouncy spring); when the sidebar opens, the title bar toggle slides out immediately (snappy spring).

### Sidebar Compact Mode

When the panel width drops below `sidebarCompactThreshold` (680pt), the
sidebar auto-collapses to an overlay. When the panel widens past the
threshold again, the sidebar auto-reopens (if it was auto-collapsed, not
manually collapsed).

**Critical:** Measure the full panel width (HStack), NOT the content area
width. Content width changes when the sidebar toggles, creating a feedback
loop: collapse -> content widens -> threshold no longer met -> expand ->
content shrinks -> threshold met -> collapse -> infinity. Panel width is stable
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

SwiftUI's `DragGesture` reports coordinates in the view's local coordinate space. As the window resizes, the view's position changes, causing SwiftUI to recalculate the gesture -- creating a feedback loop that makes the window bounce violently. **Always use AppKit mouse tracking for window resize.**

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

        // Run our own event loop -- same pattern as NSWindow.performDrag(with:).
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

1. Create `NSPanel` subclass -- borderless, non-activating, no system shadow
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

## Floating Panel Lessons Learned

### Rounded corners with VisualEffectView

`NSVisualEffectView` with `.behindWindow` blending is composited by the window server using the rectangular window frame. SwiftUI's `.clipShape()` doesn't affect the compositor -- the blur bleeds past rounded corners.

**Solution:** External shadow padding makes the panel frame larger than the visible content. `AcrylicPanelBackground` clips the acrylic material to a `RoundedRectangle` inside the padding, so the rectangular window frame never cuts into the rounded corners.

### SwiftUI DragGesture + window resize = bounce

SwiftUI's `DragGesture` tracks position in view-local coordinates. Resizing the window moves the view, which recalculates the gesture, which triggers another resize -- a feedback loop causing violent bouncing. **Always use AppKit `NSView.mouseDown` + `window.nextEvent` for window frame manipulation.**

### isMovableByWindowBackground + resize handle conflict

`isMovableByWindowBackground = true` checks `mouseDownCanMoveWindow` on the hit-tested view to decide whether to start a drag. If this returns `true` (the default), the window drag starts **before** the view's `mouseDown` fires. Setting `isMovableByWindowBackground = false` in `mouseDown` is too late. Override `mouseDownCanMoveWindow` to return `false` on the resize handle view instead.

### VisualEffectView blending in transparent windows

`.behindWindow` blending samples what's behind the *window* -- the desktop wallpaper and other apps. Since our panels use `backgroundColor = .clear` (for custom shadow rendering), any `VisualEffectView(.behindWindow)` added to overlay views inside the panel will show wallpaper colors bleeding through, even though the panel's own acrylic is visually opaque underneath.

**Solution:** Use `.withinWindow` blending for overlay views (compact sidebar, detail sheets) that sit on top of the panel's own acrylic. This samples from the window's own rendered content -- the dark acrylic -- giving the correct dark frosted appearance without wallpaper bleed-through.

Only the panel's base `AcrylicPanelBackground` should use `.behindWindow`.

---

# Panel Integration

> Panel architecture (structure, layout, display modes, search, settings, sync) combined with SwiftUI + NSPanel gotchas. Read this when working on panel layout, display mode logic, search, settings, or debugging layout/focus/popover/drag-drop/keyboard issues.

---

## Panel Structure

```
CiderPanelView
+-- HStack(spacing: 0)
|   +-- sidebarColumn (floating rounded-rect, full panel height)
|   |   +-- sidebarHeader (traffic lights + collapse toggle, top-aligned)
|   |   +-- FolderSidebarView(showBackground: false)
|   |   |   +-- Search field (top aligned with divider line)
|   |   |   +-- Folders section (hierarchical tree)
|   |   |   +-- Tags section (filter chips / collapsible)
|   |   |   +-- Pinned sources section (when linked sources are enabled)
|   |   +-- sidebarFooter (gear + "New" pill menu + view options)
|   +-- VStack (right column, top padding aligns title bar center with traffic lights)
|       +-- titleBar (animated sidebar toggle + CiderTabBar + capture button)
|       +-- Divider (14pt horizontal inset, aligned with card content edges)
|       +-- contentArea (switches by selectedTab)
|           +-- TagDetailView (when tag filters are active or Tag tab is selected)
|           +-- SourceDetailView (when a linked source is selected)
|           +-- FolderDetailView (when folder selected -- overrides tab content)
|           +-- Saved view tabs
|           |   +-- HomeDashboardView (standard saved/library views)
|           |   +-- WhiteboardTabView
|           |   +-- KanbanBoardView
|           |   +-- OnboardingTabView
|           |   +-- Blank-tab welcome state
|           +-- SearchTabContent (spawned searches)
|           +-- Tag manager tab
|           +-- Empty state (when no tabs exist)
+-- compactOverlaySidebar (< 680pt, slides over content)
+-- SearchPaletteView (overlay)
+-- Detail overlays
|   +-- bookmark detail (full-panel / slide-out / page)
|   +-- generic card detail (date/contact/todo/file/session)
|   +-- note detail/editor (full-panel / slide-out / page)
+-- PanelEdgeResizeView (all-edge resize handles)
```

---

## Panel Layout Alignment Rules

**Sidebar is the source of truth** for panel layout. When aligning elements between columns, match the right column to the sidebar -- never move the sidebar to match the tabs.

- **Tab content padding:** 12pt (Spacing.md) at TabContent level + 2pt (Spacing.xxs) at BrowserView level = 14pt total. Applied OUTSIDE the ScrollView. See `Docs/DESIGN_SYSTEM.md` section 4.1.
- **Divider inset:** `Spacing.md + Spacing.xxs` (14pt) -- matches card content edges exactly.
- **Traffic lights:** sidebarHeader uses `HStack(alignment: .top)` + `.frame(height:, alignment: .top)` so lights stay pinned regardless of conditional content.
- **View options button:** frame height = `trafficLightTapTarget` (16pt), not `buttonTapTarget` (28pt), to center with traffic lights.
- **Search bar:** FolderSidebarView has no top padding -- search bar top aligns with the divider line.
- **Sidebar live search:** `FolderSidebarView` has a `searchText: Binding<String>` TextField (not a button). `CiderPanelView` owns `@State sidebarSearchText` (raw binding for instant TextField feedback) and `@State debouncedSearchText` (150ms debounce via `Task.sleep` with cancellation). Content views (HomeDashboardView, FolderDetailView, SavedViewTabContent) receive the debounced value. Cleared on tab/folder change. `SourceDetailView` does NOT support search yet.
- **Escape priority chain:** sidebarSearchText non-empty -> clear search; else editor active -> close editor; else selection -> clear selection. Order matters -- search clears first.
- **Right column top padding:** `Spacing.sm - 1` (7pt) so title bar center aligns with traffic light circle center.

---

## Bookmark Display Modes

```
BookmarkDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via CardSizing struct
- Interpolates between 4 stops: compact -> comfortable -> large -> extraLarge
- Grid: fixed thumbnail height, proportional to card width
- Masonry: thumbnail height = exact image aspect ratio (no clamping)
- List: thumbnail width/height scale with slider
- Dual image assets per bookmark:
  - `.originals/` keeps full-size source image
  - `.thumbnails/` stores downsampled runtime PNG (currently max 720px)
  - Existing legacy thumbnails are normalized on load
- Async thumbnail loading: `.task(id: fingerprint)` + `Task.detached` + `CGImageSourceCreateWithURL` -- never `NSImage(contentsOfFile:)` on main thread

View options: Dropdown popover in sidebar footer (ViewOptionsDropdown.swift)
```

---

## Note Display Modes

```
NoteDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via NoteCardSizing struct
- Text-forward cards: wider min widths, side images instead of top images
- Images downsampled to 240px thumbnails via CGImageSource (not full NSImage)
- Card data (preview, word count, images) loaded async via NoteCardData.load()
- NoteCardData.load() calls resolvedContent once, passes to stripMarkup/countWords/imageURLs(from:) -- never call resolvedContent multiple times
- Image URL regexes are static let on Note (compiled once, not per call)
- Sorted by persisted createdAt (stored in notes index, not filesystem)

ViewOptionsDropdown is generic over DisplayModeOption protocol
```

---

## Home Display Modes

```
LibraryDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via LibraryCardSizing struct
- Delegates to CardSizing (bookmarks) and NoteCardSizing (notes)
- Grid/Masonry: BookmarkCard + NoteCardView + DateCardCardView + ContactCardCardView + TodoCardCardView
- List: Unified LibraryTableView -- all item types share the same table row layout
- Continue section: sticky 8-item recents, two-column, collapsible
- Library feed: scrollable mixed feed, filters by folder selection

### Unified Table List View (list mode)
When displayMode == .list, HomeDashboardView/FolderDetailView/SavedViewTabContent
use the shared table component instead of per-type list rows:

- LibraryTableView -- self-contained table with sticky header + scrollable rows
- LibraryTableRows -- embeddable rows for views with existing ScrollViews
- LibraryTableHeader -- column headers with draggable resize handles + column picker
- LibraryTableRow -- single row rendering any LibraryItemV2 uniformly

9 columns: Name (flexible), Type, Tags, Folder, Created, Modified, URL, Words, Priority
- Name column fills remaining space; other columns have fixed widths
- Column widths, order, and visibility persisted in CiderConfig.tableColumnConfig
- TableColumnConfig stored as JSON in UserDefaults (backward-compatible)
- Default visible: Name, Type, Tags, Created, Modified
- Hidden by default: Folder, URL, Words, Priority (toggled via + button)

LibraryItemV2 discriminated union: .bookmark(Bookmark) | .note(Note) | .dateCard(DateCard) | .contact(ContactCard) | .todo(TodoCard) | .externalFile(ExternalFile) | .vaultFile(VaultFile) | .session(BrowserSession)
- dateAnchor: Date? -- key property for calendar projection; dateCards use startAt, contacts use birthday, bookmarks/notes nil
- isCompleted: Bool -- only meaningful for dateCards/todos; used by stack surfacing rules like pinUntilDone

LibraryViewModel -- unified query engine reading from all 4 storages; rebuilds on any storage change
- Produces: filtered library feed, calendar buckets, stack resolutions
- Pre-computes `recentItems` (top 8 by updatedDate) during rebuildItems() -- HomeDashboardView reads this directly, no O(N log N) sort in body
- `filteredItemsCache` memoizes the last filter+sort result -- avoids re-filtering on unrelated body evaluations
- `matchesTextQuery` uses token-based matching: splits query on spaces, each token must match in at least one field via `localizedStandardContains` (diacritic- and case-insensitive, same as Finder)
- `externalFileContentCache` (static) caches external file disk reads during text search -- cleared in `rebuildItems()`
- `NoteCardDataCache` (Note.swift) -- cross-view cache for `NoteCardData`, keyed by `(noteID, modifiedAt)`. Used by `NoteCardView` and `NoteListRow` to avoid re-loading card data when scrolling/switching tabs.
- `NotesStorage.contentCache` -- in-memory cache for note file content, keyed by `(noteID, modifiedAt)`. Avoids repeated disk reads during search. Invalidated in `save()`, `delete()`, `scanNotes()`.
- Stacks: CardStack has matchRules + manualItemRefs, resolves items dynamically (not containers)
- SavedViews: isTabPinned: Bool controls tab bar presence; calendar is a view mode toggle, not a separate tab

State: CiderPanelView owns @State, passes Bindings to HomeDashboardView
Persistence: homeDisplayMode + homeCardSizeScale on CiderConfig
```

---

## Search Architecture

Two search systems: **SearchService** (search palette / search tab) and **LibraryViewModel.matchesTextQuery** (sidebar live search / saved view filtering). Both use the same token-based matching pattern:
- Split query on spaces into tokens
- Each token must match in at least one field via `localizedStandardContains` (Apple's diacritic- and case-insensitive matching -- same as Finder)
- Bookmarks search: title, URL, host, notes, tags
- Notes search: title + full file content (loaded via `NotesStorage.loadContent`, cached in-memory)
- Date cards: title, details, location
- Contacts: display name, relationship label, notes

**SearchService** also produces `SearchSnippet` (prefix/match/suffix with ellipsis) for body-only matches. Uses `extractSnippet(tokens:from:windowSize:)` to find the first matching token and return surrounding context.

**Scope modifiers** (`SearchScope` + `SearchService.parseScope`): Queries can contain `@`-prefixed scope modifiers that filter results before token matching:
- Entity type: `@bookmarks`, `@notes`, `@events`, `@contacts` (prefix matching: `@b` works). Multiple combine (OR).
- Folder: `@folder:Name` (multi-word, prefix match, case-insensitive). `@folder:` (bare) = all folder-assigned items. Multiple `@folder:` scopes combine (OR). Results grouped by folder with headers in Cmd+K.
- Tag: `@tag:Name` (prefix match, case-insensitive).
- Shorthand: `@f:` for folder, `@t:` for tag.
- `SearchScope` struct holds parsed scopes + `cleanQuery` (remaining text after scope extraction).
- Scope pills (blue badges) shown below search field in Cmd+K when active.
- Works in Cmd+K palette, search tabs, sidebar search, and saved view filtering (`LibraryViewModel.filteredItems` parses scopes from `textQuery`).
- Sidebar search on Inbox tab: `onlyUnassigned` is overridden when a `@folder:` scope is active.

**SpotlightIndexer** (`Services/SpotlightIndexer.swift`) indexes all items into Core Spotlight for system-wide search (Spotlight, Raycast, Alfred). Subscribes to storage `$published` properties with 2-second debounce. Gated by `CiderConfig.enableSpotlightIndexing`. Note: Core Spotlight requires a proper `.app` bundle -- SPM executables silently fail to surface items. Indexing code is ready but dormant during development builds.

---

## Settings Architecture

Settings categories live in `SettingsCategory` enum. Adding a new top-level settings section requires: (1) new case in `SettingsCategory`, (2) add to `primaryCategories`, (3) new case(s) in `SettingsSubcategory`, (4) wire in `subcategories` switch and `selectedSubcategoryContent` switch. Current categories: General, Content, Capture, Appearance, Intelligence, Data, About, Account. General subcategories: Startup, Activation, Panel Behavior, Shortcuts. Content subcategories: Bookmarks, Notes. Capture subcategories: Bookmarks, Clipboard, Storage. Appearance subcategories: Text, Sounds, Toasts. Intelligence subcategory: Features. Data subcategories: Directories, Trash, Notifications, Import/Export. Deep-link string for "View Trash" undo toast is `"data"` (navigates to `.data` category). The sync token field is persisted through `SyncService.saveSyncToken()` into Keychain; `CiderConfig.syncToken` remains as a legacy migration path, not the primary storage location.

## Cider Web Sync

Cider Web is a companion web app that lets users capture bookmarks from their phone and sync them to the desktop app. Sync is entirely optional -- disabled by default.

**Architecture:**
- `SyncService` (`Services/SyncService.swift`) -- `@MainActor` singleton using `ConvexClient`
- Authenticates once via `sync:authenticate`, then subscribes to `sync:changeSignal` over the Convex client
- Pushes local changes with `sync:push`; pulls remote changes with `sync:pull`
- Reactive by default: remote edits trigger a debounced pull when the change signal advances
- Local notes still use a 30-second dirty-note timer because editor/file-save side effects make fully event-driven push unsafe
- Conflict resolution: last-write-wins based on `updatedAt` timestamps
- Deletion tracking: bookmark, folder, and note deletions are queued in UserDefaults and pushed on the next sync pass
- Authentication: user enters a Convex site URL plus sync token in Settings -> Data -> Cider Web Sync; token is stored in Keychain
- Transport guardrails: desktop sync refuses to start unless the configured site URL is HTTPS and can be converted into a Convex deployment URL

**Sync flow:**
1. **Startup/auth** -- `SyncService.startIfEnabled()` migrates any legacy token to Keychain, validates config, creates one `ConvexClient`, authenticates with `sync:authenticate`, and installs the reactive change subscription
2. **Push** -- local bookmarks, folders, notes, and pending deletion tombstones are serialized into Convex action arguments and sent with `sync:push`
3. **Pull** -- `sync:pull` is called with the last known server timestamp to fetch new/updated/deleted bookmarks, folders, and notes
4. **Apply** -- pull handlers create or update local models from sync IDs, remove server-deleted models, and advance `lastSyncTimestamp`
5. **Steady state** -- remote edits trigger debounced pulls; local edits call `pushAfterLocalChange()`; notes also get a periodic dirty check every 30 seconds
6. Server timestamp saved to `CiderConfig.lastSyncTimestamp` for incremental pulls

**CiderConfig properties:** `syncEnabled`, `syncURL`, `lastSyncTimestamp`

**Storage sync methods:**
- `addFromSync(id:title:urlString:...)` -- creates bookmark with specific UUID, triggers enrichment
- `updateFromSync(bookmarkID:title:...)` -- updates fields, sets `updatedAt` to now
- `removeSynced(_:)` -- removes without trashing (no undo toast)
- Folders and notes have equivalent sync-specific create/update/remove paths keyed by sync IDs

**Settings UI:** `SyncSettingsView` under Data -> Cider Web Sync. Fields: Convex site URL, sync token (SecureField), enable toggle, status indicator (syncing/error/last synced), Sync Now button.

**Backend:** Convex (convex.dev). The desktop app derives a deployment URL from the configured `.convex.site` URL, then uses the Convex Swift SDK for actions and subscriptions rather than direct REST polling.

**Important:** Sync currently covers bookmarks, folders, and notes. Date cards, contacts, todos, vault files, sessions, and tags remain local-only.

---

# SwiftUI + NSPanel Gotchas

> Hard-won lessons from building SwiftUI views inside non-activating NSPanels. Reference these when debugging layout, focus, popover, drag-and-drop, or keyboard issues in the panel.

---

## Layout & Clipping

- **Animated content clipping:** Content with slide transitions (`.move(edge:)`) must have `.clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))` -- otherwise animations overflow into the shadow area drawn by `AcrylicPanelBackground`. The shadow sits underneath in the ZStack and is unaffected by clipping the content layers above it.
- **VisualEffectView in overlays:** Use `.withinWindow` blending (not `.behindWindow`) for views overlaying the panel's own content. Our window background is `.clear` for custom shadows, so `.behindWindow` samples the desktop wallpaper. Only `AcrylicPanelBackground` should use `.behindWindow`.
- **ScrollView bottom padding:** Padding on content INSIDE a ScrollView doesn't prevent clipping at the panel edge -- the scroll area itself still extends to the edge. Put bottom padding OUTSIDE the ScrollView (on the ScrollView itself) so the scroll area is inset from the panel.
- **Compact mode GeometryReader:** Measure panel width (HStack), NOT content area width. Content width changes when sidebar toggles, causing infinite collapse/expand feedback loop. Panel width is stable.
- **Prefer inline GeometryReader over PreferenceKey:** `onPreferenceChange` fires with the `defaultValue` (often `0`) before the real measurement arrives, causing incorrect initial state. Inline `GeometryReader { proxy in let x = proxy.size.width ... }` is simpler and avoids this race.
- **GeometryReader threshold anti-oscillation:** When a threshold controls layout (e.g., 1 vs 2 columns), set it high enough that sidebar show/hide (~200pt delta) can't flip the result. Otherwise content width jumps when sidebar toggles, causing column flicker.
- **MasonryLayout cache:** `computeFrames` has no width-only cache across layout passes -- subview sizes can change independently (e.g., `BookmarkCard.@State cardWidth` updating via GeometryReader). However, `placeSubviews` skips recomputation when width matches `sizeThatFits` (safe within same layout pass). `sizeThatFits` always recomputes to catch subview size changes.
- **Sticky section headers:** `LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders])` makes `Section { } header: { }` headers pin at the top during scroll. Used in FolderDetailView for folder header + sub-folder cards. The header needs an opaque background to prevent content showing through when pinned.

## Context Menus

- **Never use SwiftUI `.contextMenu`** in lazy containers -- it caches content and goes stale after data changes. Use the shared `CardContextMenu` (`Utilities/CardContextMenu.swift`) which builds a fresh native `NSMenu` on every right-click.
- **NSView overlays:** When overlaying `NSViewRepresentable`, override `hitTest` to return `nil` for non-target events -- otherwise the overlay blocks left clicks, hovers, and drags from reaching SwiftUI content underneath.

## Focus & Keyboard

- **@FocusState in NSPanel:** Non-activating panels need a delay before focus takes effect -- use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }`
- **Escape key in NSPanel:** `.onExitCommand` does NOT work with `.nonactivatingPanel` -- use a hidden `Button("") { ... }.keyboardShortcut(.escape, modifiers: [])` in `.background {}` instead.
- **Modifier detection in Button actions:** Use `NSEvent.modifierFlags` (static property) to check `.command` / `.shift` at click time. Works inside Button action closures without needing gesture composition.

## Popovers

- **Always use SwiftUI `.popover()`, never manual NSPopover:** SwiftUI's `.popover(isPresented:, arrowEdge:)` positions correctly for views inside `NSHostingView` in non-activating panels. Manual `NSPopover.show(relativeTo:of:)` is unreliable -- the NSView's reported frame in the AppKit hierarchy is misaligned with the visual position due to coordinate system inconsistencies between the flipped `NSHostingView` and its non-flipped NSView children.
- **ViewBridge/RemoteViewService crash in `.popover()` content (non-activating panel):** SwiftUI popovers render content in a remote XPC process (RemoteViewService). Two things crash it: (1) `@FocusState` + async `.task { focused = true }` inside popover forms -- async focus events fire into a partially-ready XPC context; (2) `withAnimation` / `.animation()` on content that changes height -- animated popover resizes over XPC fail and call back through a nil function pointer (crash at `0x00000000`, "Unable to obtain a task name port right" in logs). Fix: no `@FocusState` in popover forms, no animation on content changes. Simple SwiftUI popovers with static content (e.g. `ViewOptionsDropdown`) are fine. Also: never use `DatePicker(.field)` or `DatePicker(.compact)` inside a popover in a non-activating panel -- both open popup calendars that crash the same way. Use plain `TextField` with date string parsing instead.
- **+New popover (`NewItemPopover.swift`):** 3x2 grid of type cards: Bookmark, Note, Event, Contact, Folder, Tab. No `@FocusState` or animations anywhere in the popover. Event form uses plain text fields for date ("Feb 21, 2026") and time ("2:30 PM") with `DateFormatter` multi-format parsing. Tab form creates a `SavedView` (isTabPinned: true) with selected entity type filter; panel navigates immediately to the new tab.

## Drag & Drop

- **Custom UTIs in `.onDrop`:** `hasItemConformingToTypeIdentifier()` and `registeredTypeIdentifiers.contains()` both fail for unregistered custom UTIs (e.g., `com.cider.multi-drag`). Encode payloads in `public.utf8-plain-text` with a distinctive prefix (e.g., `cider-multi-drag:JSON`) and detect via text parsing in drop handlers.
- **Drag preview clipping:** `scaleEffect`, `rotationEffect`, and `offset` on `.onDrag(preview:)` views push content outside the view's natural bounds. macOS clips the preview window to those bounds. Add explicit `.padding()` before transforms to prevent clipping.
- **Multi-drag provider types:** Don't register single-item type identifiers on multi-drag providers -- the single-item drop handler fires first (by order in `handleFolderDrop`) and intercepts the drop, ignoring the multi-drag payload.
- **onDrop concurrency:** `loadDataRepresentation` callbacks are non-isolated. Capture view model references locally before the closure, then do lookups inside `Task { @MainActor in }` to avoid main-actor-isolation warnings.

## Mouse Events & NSViewRepresentable

- **Mouse event capture on NSViewRepresentable:** For overlays that MUST capture mouse events (e.g., cover image drag), override `mouseDownCanMoveWindow` -> `false`, `hitTest` -> return `self`, `acceptsFirstMouse` -> `true`, and use `.activeAlways` tracking area (not `.activeInKeyWindow` -- non-activating panels are never key). Use `window.nextEvent(matching:)` event loop pattern (see `PanelEdgeResizeView` and `CoverRepositionNSView`).

## View Lifecycle & Data

- **Card data refresh:** Use `.task(id: note.modifiedAt)` not `.task(id: note.id)` so card data reloads after edits.
- **`.task(id:)` for file replacement:** When file content changes but the path stays the same (e.g., replacing a cover image), include `updatedAt` timestamp in the task ID -- not just the file path.
- **Home tab kept alive:** `HomeDashboardView` is always in the view tree (ZStack with `opacity(isHomeActive ? 1 : 0)` + `allowsHitTesting`). Switching tabs doesn't destroy it -- thumbnails, card data, and scroll position persist. Other tabs (saved views, search, external sources) still create/destroy on demand. `isHomeActive = selectedTab == .home && selectedFolderID == nil && selectedSourceID == nil`.
- **Folder view condition order:** In `tabContentBody`, check `selectedFolderID != nil` BEFORE the ZStack that contains Home -- otherwise Home renders instead of FolderDetailView when a folder is selected on the Home tab.
- **Tab deselection in folder view:** CiderTabBar takes `selectedFolderID` binding. `isSelected = selectedTab == tab && selectedFolderID == nil`. Clicking a tab sets `selectedFolderID = nil` so re-clicking the same tab works to exit folder view.
- **Inline note editor:** Notes open inline within CiderPanelView via push/pop navigation (`editingNoteID` state). Editor takes over the content area; title bar swaps to back button + editable title + formatting controls. Escape or back button closes the editor, flushes save, and returns to the previous view.
- **Text concatenation:** `Text("a") + Text("b")` is deprecated in macOS 26. Use `Text(AttributedString)` with per-range attributes instead.

## Card & Container Contracts

- **Card container contract:** Every card view (BookmarkCard, NoteCardView, DateCardCardView, ContactCardCardView) MUST use `.cardContainer(isHovered:isSelected:isDropTargeted:)` -- never inline a `RoundedRectangle` with manual background/border/clip. Border priority inside `cardContainer`: selected > dropTargeted > hovered > default. `isDropTargeted` defaults to `false` so existing call sites need no changes when adding drop support.
- **BookmarkCard thumbnail drop is self-contained:** `BookmarkCard` calls `BookmarksStorage.shared.assignThumbnail(...)` directly and posts `.showBookmarkCaptureToast` itself. There are NO `onAssignThumbnailFrom*` callback properties -- do not add them back. Any view that renders `BookmarkCard` gets drag-and-drop thumbnail assignment for free with no wiring.
- **Bookmark image memory model:** Render bookmark cards from `thumbnailFileURL` (downsampled asset), not `originalImageFileURL`. Full-size originals are for explicit user actions (open/export) only.
- **Shared view parameter changes:** Shared views like `HomeDashboardView`, `FolderDetailView`, and `SavedViewTabContent` are used by `CiderPanelView` (and potentially multiple call sites within it). When adding required parameters, update ALL call sites.

## AppKit Integration Gotchas

- **NSOpenPanel from non-activating panel:** Call `NSApp.activate(ignoringOtherApps: true)` before `runModal()` -- otherwise the file picker sidebar isn't fully interactive (requires multiple clicks). Don't set `panel.level = .floating` on the open panel.
- **Shadow shapes use literal `Color.black`** -- this is correct, not a CiderColors violation. The custom shadow pattern (blurred black RoundedRectangle) is intentional.
- **AppKit Reduce Motion:** For `NSAnimationContext` code (panel collapse), check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` -- `@Environment(\.accessibilityReduceMotion)` is SwiftUI-only.
- **SourceKit false positives:** "Cannot find 'CiderFont' in scope" (and similar cross-file type errors) are SourceKit indexing noise, not real build errors. Ignore them -- verify with `swift build` instead.
- **System sounds:** `NSSound` fails silently in `.accessory` activation apps (`AddInstanceForFactory` error). Use `AudioServicesPlaySystemSound` (AudioToolbox) instead. See `CiderSoundEffect.swift`.
- **`nonisolated static` for View helpers called off main thread:** Pure utility static methods on SwiftUI `View` structs that are called from `NSItemProvider` callbacks (non-isolated background threads) must be marked `nonisolated static`. Without it, the compiler emits a main-actor isolation warning. Example: `BookmarkCard.preferredImageFileExtension(for:)`.
- **Detail overlays:** Bookmark/note detail views display inline within the CiderPanel as full-panel overlays, slide-out sheets, or page-style views. No separate floating detail panel -- all detail display happens within the main panel's view hierarchy.

## Caching & Performance

- **CiderFont scale is cached:** `CiderFont._cachedScale` (`nonisolated(unsafe) static var`) is set at startup and refreshed by `CiderFont.invalidateScale()` at the top of `handleConfigChanged()`. Font tokens read the cached value -- no UserDefaults decode per render. If you add a new config-driven font property, call `invalidateScale()` from `handleConfigChanged()`. Only `heroDisplay(scale:)` takes an explicit parameter; all other tokens respond automatically.
- **StoragePaths vault caching:** `StoragePaths` caches per-type directory URLs in `_cachedTypeURLs` and the vault root in `_cachedVaultURL` (both `nonisolated(unsafe) static var`). Use `cachedDirectoryURL(for:)` in render paths and view closures. Invalidated by `StoragePaths.invalidateCachedDirectory()` in `handleConfigChanged()`. `Bookmark.thumbnailFileURL`/`originalImageFileURL` and `Note.resolvedContent`/`imageURLs` use these cached paths. Never call `CiderConfig.load()` in view body or computed properties that run during render -- use cached paths or `@State config` instead.
- **Undo toast progress bar:** Both capture toast and undo toast use a repeating `Timer` at `BookmarksToastDesign.reviewProgressTickInterval` (1/30s). Model is an `ObservableObject` with `@Published var progress: CGFloat = 1`. Hover pauses the timer; unhover resumes. Match this pattern for any future timed toast.

## Build & Project

- **Xcode + SPM hybrid project:** `Cider.xcodeproj` wraps the SPM package for code signing. Only open one at a time -- having both `Package.swift` and `.xcodeproj` open in Xcode simultaneously causes "Couldn't load package" / "Missing package product" errors.
- **SWIFT_MODULE_NAME on app target:** The Xcode app target sets `SWIFT_MODULE_NAME = CiderApp` to avoid a Swift module name collision with the SPM library (both would default to "Cider" from `PRODUCT_NAME = Cider`). Do not remove this setting.
- **Bundle.module vs Bundle.main:** Resources excluded from SPM via `exclude:` in `Package.swift` (TipTapEditor, ExcalidrawEditor, ReaderMode) are owned by the Xcode target. Those call sites use `Bundle.main`, not `Bundle.module`. If adding new SPM-excluded resources, update the call site too.
- **Nested types in dead files:** Before deleting a "dead" file, grep for ALL types it defines (not just the primary struct). BookmarksBrowserView.swift contained `BookmarkThumbnailView` and `BookmarkVisualStyle` used elsewhere.

## Storage & Data Integrity

- **Delete is non-destructive:** `BookmarksStorage.remove()`, `removeAll()`, `NotesStorage.delete()`, `DateCardStorage.deleteDateCard()`, and `ContactStorage.deleteContact()` all delegate to `TrashStorage` and return `@discardableResult TrashItem` (or `TrashItem?`). Callers capture the result and pass it to `CiderUndoManager.shared.record()` to enable undo. Never add a direct file-deletion path -- always go through TrashStorage. For bulk deletes across entity types, call storage methods directly (not ViewModel wrappers) and collect all trash items into a single `bulkDeletedToTrash` recording -- `CiderUndoManager` only tracks one pending action.
- **Image bookmarks have empty `urlString`:** `addImageBookmark(title:)` creates with `urlString: ""`. Both `loadFromDisk` and `buildSnapshotFromFiles` must append empty-URL bookmarks from metadata JSON after the HTML merge loop -- `NetscapeBookmarksCodec.decode` skips empty hrefs.
- **Clipboard monitor suspension:** `ActiveBrowserCaptureService.captureViaShortcut()` restores the pasteboard after reading browser URL, incrementing `changeCount`. When `BookmarksClipboardMonitor` suspension expires, it must reset `lastChangeCount` to current value to avoid re-detecting stale clipboard changes. Image data may also be lazily provided by source apps -- the monitor schedules a 400ms retry via `DispatchWorkItem`.
- **BookmarksStorage class boundary:** The `BookmarksStorage` class closes around line 1600. Everything after is file-private types (`BookmarkEnrichmentPayload`, `EnrichmentRetryThresholds`, `BookmarkMetadataParser`, `NetscapeBookmarksCodec`). When adding instance methods, insert them BEFORE the class `}` -- not at the end of the file -- or they'll silently land inside a private enum and `bookmarks`/`persist` won't be in scope.
- **ActiveBrowserCaptureService browser candidate filter:** `target(from:)` requires `activationPolicy == .regular` AND `bundleURL` exists on disk before creating a `BrowserTarget`. This blocks ghost Dock Extras (uninstalled apps still registered) and XPC/helper processes (`.accessory`/`.prohibited` policy) from reaching the AppleScript layer, where they would trigger macOS "Where is <App>?" system pickers. Preserve both guards when modifying this function.

## NSView / AppKit Deep

- **CiderPanel WKWebView drag exclusion:** `isInDraggableArea()` in `CiderPanel.swift` checks `if v is WKWebView { return false }` -- without this, dragging inside the TipTap editor moves the entire panel instead of interacting with the editor content.
- **Carbon hotkey fallback:** `BookmarksHotkeyDetector` and `NotesHotkeyDetector` fall back to Carbon `RegisterEventHotKey` / `InstallEventHandler` when `CGEventTap` creation fails (e.g., no Accessibility permission). Both detectors now work without full accessibility access -- Opt+N and Opt+B hotkeys register via Carbon API in that case.
- **Layer-backed NSView transparency:** `.clear` CGContext blend mode does NOT punch through to show content below in `wantsLayer = true` views -- it clears the layer to transparent but the composited result depends on window blending, not the pixels below. To create a "hole" in a dim overlay (e.g. screen capture selection), draw the dim as 4 rects around the selection instead of fill-all + clear-hole.

---

## File References

- `CiderPanel.swift` -- Main NSPanel implementation (resizable, draggable, cross-monitor movement)
- `CiderPanelView.swift` -- Main panel view with sidebar, tab bar, inline note editor, resize handles
- `AcrylicPanelBackground.swift` (`Views/Shared/`) -- Shared acrylic + shadow background component
- `Docs/Design/ACRYLIC_IMPLEMENTATION.md` -- Full shadow/border/material documentation

---

**Last Updated**: March 2026

**This document reflects the actual Cider architecture: Swift 6.2, SwiftUI, AppKit, Combine, UserDefaults, plus four SPM dependencies (Sparkle, convex-swift, mlx-swift-lm, Yams).**
