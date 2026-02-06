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
| Target | macOS 14+ (Sonoma and later) | Modern APIs, broad compatibility |

---

## Project Structure

```
Cider/
├── App/
│   ├── CiderApp.swift              # @main entry point
│   ├── AppDelegate.swift           # NSApplicationDelegate, menu bar setup
│   ├── CommandPalettePanel.swift   # Command palette NSPanel (non-activating)
│   └── SettingsWindow.swift        # Settings NSWindow
│
├── Views/
│   ├── CommandPalette/
│   │   ├── CommandPaletteView.swift      # Root palette composition
│   │   ├── PaletteBackgroundView.swift   # Acrylic background
│   │   ├── PaletteSearchBar.swift        # Search field
│   │   ├── PaletteAppsRow.swift          # Pinned apps horizontal row
│   │   ├── PaletteContentArea.swift      # Window list content
│   │   └── PaletteFooterBar.swift        # Footer with actions
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift            # Main settings layout
│   │   ├── GeneralSettingsView.swift     # General preferences
│   │   ├── AppearanceSettingsView.swift  # Theme, sizing
│   │   └── AdvancedSettingsView.swift    # Power user options
│   │
│   └── PinnedAppsView.swift              # Pinned apps list
│
├── ViewModels/
│   ├── CommandPaletteViewModel.swift     # Palette state and actions
│   ├── PinnedAppsViewModel.swift         # Pinned apps state
│   ├── WindowListViewModel.swift         # Window enumeration, actions
│   └── SettingsViewModel.swift           # Settings state
│
├── Services/
│   ├── AppLauncher.swift                 # Launch/focus apps
│   ├── ClipboardManager.swift            # Clipboard history helpers
│   ├── DockManager.swift                 # Dock integration helpers
│   ├── WindowManager.swift               # AXUIElement + CGWindowList wrapper
│   ├── WindowPreviewService.swift        # Window thumbnail capture
│   ├── MonitorManager.swift              # Multi-monitor detection
│   ├── DoubleTapDetector.swift           # Modifier key double-tap detection
│   ├── LauncherEngine.swift              # App launch/search plumbing
│   └── SystemStatus.swift                # System info helpers
│
├── Models/
│   ├── WindowInfo.swift                  # Window metadata from AX API
│   ├── AppInfo.swift                     # App metadata (bundle ID, icon, path)
│   ├── MonitorInfo.swift                 # Display metadata
│   └── CiderConfig.swift                 # User preferences (Codable)
│
├── Utilities/
│   ├── Constants.swift                   # Design tokens, sizes, animations
│   ├── AccessibilityHelpers.swift        # AXUIElement convenience wrappers
│   ├── ColorExtractor.swift              # Extract accent color from icons
│   ├── Shell.swift                       # Shell utilities
│   └── VisualEffectView.swift            # NSVisualEffectView wrapper
│
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Cider.entitlements
```

---

## Key Architectural Patterns

### 1. NSPanel for Command Palette

The command palette uses `NSPanel` with non-activating behavior:

```swift
class CommandPalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow
    }

    override var canBecomeKey: Bool { true }  // Allow text input
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
let panel = CommandPalettePanel()
let windowListViewModel = WindowListViewModel()
let pinnedAppsViewModel = PinnedAppsViewModel()
let viewModel = CommandPaletteViewModel(
    windowListViewModel: windowListViewModel,
    pinnedAppsViewModel: pinnedAppsViewModel
)
let contentView = CommandPaletteView(viewModel: viewModel)
panel.contentView = NSHostingView(rootView: contentView)
```

### 3. Double-Tap Activation

Cider activates via double-tap of a modifier key (currently: Option):

```swift
let detector = DoubleTapDetector(key: .option, maxInterval: 0.3) {
    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
}
detector.start()
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Use decodeIfPresent with defaults for backward compatibility
        autoHideApps = try container.decodeIfPresent(Bool.self, forKey: .autoHideApps) ?? false
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        paletteSize = try container.decodeIfPresent(PaletteSize.self, forKey: .paletteSize) ?? .medium
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
│  • Detects modifier key double-tap                               │
│  • Fires callback to AppDelegate                                 │
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
2. If false, show explanation and link to System Settings > Accessibility
3. Without Accessibility, window management is non-functional

---

## Settings Storage

Settings are stored in UserDefaults as JSON:

```swift
static func load() -> CiderConfig {
    guard let data = UserDefaults.standard.data(forKey: "CiderConfig"),
          let config = try? JSONDecoder().decode(CiderConfig.self, from: data) else {
        return CiderConfig()
    }
    return config
}

func save() {
    if let data = try? JSONEncoder().encode(self) {
        UserDefaults.standard.set(data, forKey: "CiderConfig")
        UserDefaults.standard.synchronize()  // Immediate save
    }
}
```

---

## Build & Run

```bash
# Open in Xcode
open Package.swift

# Or build from command line
swift build
swift run
```

Grant Accessibility permission when prompted for window management to work.
