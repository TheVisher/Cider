# Cider Architecture

> **Read this second.** This document explains how Cider is built — project structure, key patterns, and technical decisions.

---

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Language | Swift | Native performance, Apple API access |
| UI Framework | SwiftUI | Modern, declarative, handles animations well |
| System Integration | AppKit | NSPanel, NSPasteboard, NSWorkspace, AXUIElement |
| Reactive State | Combine | Native to Apple ecosystem, integrates with SwiftUI |
| Target | macOS 26+ | Modern APIs, Swift 6.2 concurrency |

---

## Project Structure

```
Cider/
├── App/
│   ├── CiderApp.swift                  # @main entry point
│   ├── AppDelegate.swift               # NSApplicationDelegate, menu bar setup
│   ├── CommandPalettePanel.swift       # Command palette NSPanel (non-activating)
│   ├── WindowCyclingPanel.swift        # Window cycling NSPanel (non-activating)
│   └── SettingsWindow.swift            # Settings NSPanel
│
├── Views/
│   ├── CommandPalette/
│   │   ├── CommandPaletteView.swift      # Root palette composition + key handling
│   │   ├── PaletteBackgroundView.swift   # Acrylic background + custom shadow
│   │   ├── PaletteSearchBar.swift        # Search field with real-time filtering
│   │   ├── PaletteAppsRow.swift          # Pinned apps + folders, drag-to-reorder
│   │   ├── PaletteContentArea.swift      # Window list, tabs, drag between monitors
│   │   └── PaletteFooterBar.swift        # Footer with actions
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift              # Main settings layout (5 tabs)
│   │   ├── GeneralSettingsView.swift       # General preferences
│   │   ├── AppearanceSettingsView.swift    # Theme, sizing
│   │   ├── PinnedAppsSettingsView.swift    # Pinned apps management
│   │   ├── AdvancedSettingsView.swift      # Power user options
│   │   └── AboutSettingsView.swift         # About and credits
│   │
│   ├── WindowCycling/
│   │   └── WindowCyclingOverlayView.swift  # Option+Tab window cycling UI
│   │
│   └── PinnedAppsView.swift                # Pinned apps list view
│
├── ViewModels/
│   ├── CommandPaletteViewModel.swift       # Palette state, search, keyboard nav, folders
│   ├── PinnedAppsViewModel.swift           # Pinned apps state
│   ├── WindowListViewModel.swift           # Window enumeration, grouping, actions
│   └── SettingsViewModel.swift             # Settings state
│
├── Services/
│   ├── AppLauncher.swift                   # Launch/focus apps
│   ├── ClipboardManager.swift              # Clipboard history helpers (unused)
│   ├── DockManager.swift                   # Dock integration helpers
│   ├── DoubleTapDetector.swift             # Modifier key double-tap/single-tap detection
│   ├── LauncherEngine.swift                # App launch/search plumbing (unused)
│   ├── MonitorManager.swift                # Multi-monitor detection
│   ├── OptionTabDetector.swift             # Option+Tab key combination detector
│   ├── SystemStatus.swift                  # System info helpers (unused)
│   ├── WindowCyclingManager.swift          # Window cycling state machine
│   ├── WindowManager.swift                 # AXUIElement + CGWindowList wrapper
│   └── WindowPreviewService.swift          # Window thumbnail capture (service only, no UI)
│
├── Models/
│   ├── WindowInfo.swift                    # Window metadata from AX API
│   ├── AppInfo.swift                       # App metadata (bundle ID, icon, path)
│   ├── MonitorInfo.swift                   # Display metadata
│   └── CiderConfig.swift                   # User preferences (Codable)
│
├── Utilities/
│   ├── Constants.swift                     # Design tokens, sizes, animations, colors
│   ├── AccessibilityHelpers.swift          # AXUIElement convenience wrappers
│   ├── ColorExtractor.swift                # Extract accent color from icons
│   ├── HighlightedText.swift               # Search result text highlighting
│   ├── PaletteFocusState.swift             # Focus management state
│   ├── Shell.swift                         # Shell utilities
│   └── VisualEffectView.swift              # NSVisualEffectView wrapper
│
└── Resources/                              # Currently empty (SPM handles bundling)
```

---

## Key Architectural Patterns

### 1. NSPanel for Command Palette

The command palette uses `NSPanel` with non-activating behavior:

```swift
final class CommandPalettePanel: NSPanel {
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

        isMovable = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }   // Allow text input
    override var canBecomeMain: Bool { false }
}
```

**Key properties:**
- `.borderless` — No system chrome, we draw everything
- `.nonactivatingPanel` — Doesn't steal focus from other apps
- `hasShadow = false` — We draw custom shadows as blurred shapes
- `backgroundColor = .clear` — Transparent window for custom background

### 2. NSHostingView for SwiftUI Content

SwiftUI views are hosted inside NSPanel via `NSHostingView`:

```swift
// From AppDelegate.configureCommandPalette() and updateCommandPaletteSize()
let viewModel = CommandPaletteViewModel(
    windowListViewModel: windowListViewModel,
    pinnedAppsViewModel: pinnedAppsViewModel
)
let panel = CommandPalettePanel()

let config = CiderConfig.load()
let shadowPadding = CommandPaletteDesign.shadowPadding
let paletteView = CommandPaletteView(viewModel: viewModel,
                                      paletteSize: config.paletteSize,
                                      textSize: config.textSize)
    .padding(.horizontal, shadowPadding)
    .padding(.top, 20)
    .padding(.bottom, shadowPadding + 15)

let hostingView = CommandPaletteHostingView(rootView: paletteView)
panel.contentView = hostingView
```

### 3. Double-Tap Activation

Cider activates via double-tap of a modifier key (currently: Option):

```swift
// From AppDelegate.startDoubleTapDetection()
let config = CiderConfig.load()
doubleTapDetector = DoubleTapDetector(
    key: .option,
    maxInterval: 0.3,
    mode: config.activationMode
) { [weak self] in
    Task { @MainActor in
        self?.toggleCommandPalette()
    }
}
doubleTapDetector?.start()
```

### 4. Services Are UI-Independent

Every service can be called without any UI:

```swift
// Good: Clean interfaces
windowManager.focus(window: window)
windowManager.close(window: window)
windowManager.moveWindow(window, to: monitor)

// Bad: UI dependencies
windowManager.focusSelectedItem()  // Don't do this
```

### 5. Configuration with Backward Compatibility

`CiderConfig` uses custom decoding to handle new fields gracefully:

```swift
struct CiderConfig: Codable {
    var autoHideApps: Bool = false
    var showMenuBarIcon: Bool = true
    var textSize: TextSize = .medium
    var paletteSize: PaletteSize = .medium
    var activationMode: ActivationMode = .doubleTap
    var enableOptionTabCycling: Bool = true
    var optionTabCycleAllScreens: Bool = true
    var rememberPaletteState: Bool = false

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Use decodeIfPresent with defaults for backward compatibility
        autoHideApps = try container.decodeIfPresent(Bool.self, forKey: .autoHideApps) ?? false
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        paletteSize = try container.decodeIfPresent(PaletteSize.self, forKey: .paletteSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        enableOptionTabCycling = try container.decodeIfPresent(Bool.self, forKey: .enableOptionTabCycling) ?? true
        optionTabCycleAllScreens = try container.decodeIfPresent(Bool.self, forKey: .optionTabCycleAllScreens) ?? true
        rememberPaletteState = try container.decodeIfPresent(Bool.self, forKey: .rememberPaletteState) ?? false
    }
}
```

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   User Double-Taps Option Key                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DoubleTapDetector                           │
│  • Detects modifier key double-tap or single-tap                 │
│  • Fires closure callback to toggle palette                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CommandPalettePanel                            │
│  • Shows/hides on mouse's current screen                        │
│  • Hosts SwiftUI content view                                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CommandPaletteViewModel                         │
│  • Manages search query                                          │
│  • Filters window list                                           │
│  • Handles user actions                                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   WindowListViewModel                            │
│  • Fetches windows via WindowManager                             │
│  • Groups by monitor and app                                     │
│  • Refreshes on 1-second timer                                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       WindowManager                              │
│  • CGWindowListCopyWindowInfo for window enumeration            │
│  • AXUIElement for window manipulation (focus, close, move)     │
│  • Accessibility API for precise control                         │
└─────────────────────────────────────────────────────────────────┘

**Note:** A parallel flow exists for Option+Tab window cycling:
OptionTabDetector → AppDelegate → WindowCyclingManager → WindowCyclingPanel
```

---

## Multi-Monitor Support

Cider detects monitors via `MonitorManager` and:

1. Opens the command palette on the screen where the mouse is
2. Groups windows by their current monitor
3. Allows moving windows between monitors via context menu

```swift
// Find screen containing mouse
let mouseLocation = NSEvent.mouseLocation
let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    ?? NSScreen.main
    ?? NSScreen.screens.first
```

---

## Required Permissions

| Permission | Why | When Requested |
|------------|-----|----------------|
| Accessibility | Window enumeration, focus, close, move via AXUIElement | First launch |
| Screen Recording | Window thumbnails (optional) | When user enables previews |

**First launch flow:**
1. Check `AXIsProcessTrusted()`
2. If false, call `AXIsProcessTrustedWithOptions()` with prompt flag to trigger system dialog
3. System shows its own accessibility permission dialog linking to System Settings
4. Without Accessibility, window management is non-functional

---

## Settings Storage

Settings are stored in UserDefaults as JSON:

```swift
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
        UserDefaults.standard.synchronize()  // Force immediate write
    }
}
```

---

## Build & Run

```bash
# Build from command line
swift build

# Run (redirect output to avoid Terminal noise)
$(swift build --show-bin-path)/Cider &>/dev/null &

# Kill running instance
pkill -x Cider
```

Grant Accessibility permission when prompted for window management to work.
