# Cider — macOS Shell Replacement App (Legacy Prompt)

> **Legacy note:** This prompt describes the original sidebar concept and glass styling. It is not aligned with the current command‑palette direction. Use Docs/VISION.md and Docs/ARCHITECTURE.md as the source of truth.

## Project Overview

Build a native macOS app called **Cider** that replaces the Dock, Menu Bar, Spotlight, and Stage Manager with a unified sidebar interface. The app should be a floating glass panel anchored to the left or right edge of the screen with modular, vertically stacked components.

**The name "Cider"** — phonetically "side-r" (it's on the side), made from apples (macOS), refreshing/crisp connotation. The logo is an amber/gold S-shaped apple peel spiral.

---

## Tech Stack

- **Language:** Swift
- **UI Framework:** SwiftUI for component views, AppKit for system-level integration (window management, accessibility APIs, panel behavior)
- **Architecture:** MVVM with Combine for reactive state
- **Target:** macOS 14+ (Sonoma and later)
- **Build System:** Xcode / Swift Package Manager

This must feel completely native. No Electron, no web views, no cross-platform frameworks. Use NSPanel for the sidebar window so it floats above other windows without taking focus. Use the Accessibility API (AXUIElement) for window management. Use NSPasteboard for clipboard. Use NSMetadataQuery for Spotlight search integration.

---

## V0.1 Scope — What to Build Now

Build a minimal but functional sidebar that proves the concept. Just these features:

### 1. Floating Sidebar Shell
- An always-on-top `NSPanel` (`.nonactivatingPanel`) that floats on the left or right screen edge
- Full height of the screen (minus menu bar)
- Fixed width (~72px collapsed, ~280px expanded)
- **Glassmorphism appearance:** Use `NSVisualEffectView` with `.behindWindow` material for the native macOS frosted glass look. The sidebar should feel like a translucent glass panel, consistent with macOS Tahoe/Sonoma vibrancy
- Rounded corners on the inner edge (the edge not touching the screen border)
- No title bar, no standard window chrome
- Should not appear in the Dock or Cmd+Tab switcher (set `activationPolicy` to `.accessory` or `.prohibited`)
- Should not steal focus from the active app when clicked

### 2. Pinned Apps (Dock Replacement)
- A configurable grid of app icons displayed as squircles (rounded-rect with continuous corners, like iOS/macOS app icons)
- Users can add/remove apps (store the list in UserDefaults or a JSON config file)
- Click an app icon to launch it or bring it to front if already running
- Show a small dot indicator beneath running apps
- Right-click context menu: "Remove from Cider", "Show in Finder"
- Drag to reorder
- For the initial version, provide a way to import current Dock apps from `~/Library/Preferences/com.apple.dock.plist`

### 3. Window List (Stage Manager Replacement)
- Display all open windows grouped by application, as a tree view: App Name → Window titles
- Collapse/expand each app group
- Click a window entry to focus it (bring it to front and focus the app)
- Show basic window controls on hover: a close button (×)
- Use `CGWindowListCopyWindowInfo` to enumerate windows
- Use `AXUIElement` API to focus, minimize, and close windows
- Refresh the list reactively when windows open/close/change

### 4. Hover Expand/Contract Behavior
- The sidebar has multiple vertically stacked component sections
- When hovering over any component, it smoothly expands (takes more vertical space) while other components contract
- Use SwiftUI animation with ~300ms spring/easeInOut transitions
- All components remain visible at all times — nothing fully collapses to zero height
- Default (no hover): all components share space roughly equally
- On hover: hovered component gets ~2.5x flex weight, others get ~0.5–0.6x

---

## Full Feature Vision (DO NOT BUILD YET — Context Only)

These are planned features for future versions. They are listed here so you understand the architecture direction and don't paint yourself into a corner. Structure the code to accommodate these later.

### Status Bar (Menu Bar Replacement) — v0.3
- Live clock with date on hover
- System status icons: WiFi, Bluetooth, battery, volume
- Menu bar app tray (surface background apps like 1Password, Bartender)
- Quick actions: Lock, Sleep, Settings
- Mini calendar popover

### App Launcher / Search (Spotlight Replacement) — v0.2
- Triggered by ⌘K (configurable), clicking search bar, or hot corner
- Full-text search across apps, files, settings, recent documents
- Category browsing when no query entered
- Pin apps to sidebar from search results
- Keyboard navigation: ↑↓ navigate, ↵ open, ⌘↵ pin, ⇥ categories, ⎋ close
- Data sources: NSMetadataQuery (Spotlight index), /Applications file watcher

### Clipboard History — v0.2
- Show current clipboard contents as a preview
- Keep history of last 20–50 items (configurable)
- Click any item to re-copy it to clipboard
- Filter by type: text, images, files
- Pin important items
- Sensitive content detection (optionally skip passwords)
- Data source: NSPasteboard polling

### File Drop Zone — v0.3
- A visual drop target area in the sidebar
- Drag files from Finder/desktop into the drop zone to "stage" them
- Staged files persist until manually cleared
- Drag files back out of the drop zone into any app or folder
- Multi-file support, individual remove buttons, clear all
- Spring-loaded behavior: hover over a pinned app icon while dragging to open that app

### Window Grouping & Tiling — v0.3
- Drag one window entry onto another to create a group
- Groups can be named
- Tiling options: left half, right half, quadrants, custom grid
- "Minimize All", "Tile All" bulk actions

### Extension System — v0.4
- Plugin architecture for user-created sidebar components
- `CiderExtension` protocol: id, name, icon, render(), onHover(), onFileDrop(), settingsView()
- `ExtensionContext` provides: display state, clipboard service, drop zone service, window manager service, persistent storage, sandboxed networking
- Extensions packaged as `.ciderext` bundles with manifest.json
- Built-in extensions: Now Playing, Weather, System Stats, Quick Notes
- Security: sandboxed execution, permission-based access

### Pawkit Integration — v1.0
- Cider is the capture/interaction layer; Pawkit (a separate app) is the organization/storage brain
- Clipboard → 🐾 button to save URLs/text to Pawkit
- Drop Zone → save staged files to Pawkit library
- Pawkit extension panel: recent items, tag buttons, search, quick actions
- Communication via local API, REST API, or shared SQLite database

### Multi-Monitor Support — v0.3
- Choose which monitors show the sidebar
- Option for independent sidebar per monitor
- Drag windows between sidebars to move between monitors

### Setup Flow — v1.0
- Welcome screen explaining the concept
- Permission requests: Accessibility (required), Automation, Screen Recording (optional)
- "Replace Dock?" prompt that hides the system Dock
- Import current Dock apps into Cider pinned apps
- Choose sidebar position (left/right)
- Tutorial overlay

### Dock Hiding
```swift
// Hide the Dock when Cider replaces it
func hideDock() {
    shell("defaults write com.apple.dock autohide -bool true")
    shell("defaults write com.apple.dock autohide-delay -float 1000")
    shell("defaults write com.apple.dock autohide-time-modifier -float 0")
    shell("killall Dock")
}

func restoreDock() {
    shell("defaults delete com.apple.dock autohide-delay")
    shell("defaults delete com.apple.dock autohide-time-modifier")
    shell("killall Dock")
}
```

---

## Architecture Guidelines

### Project Structure
```
Cider/
├── App/
│   ├── CiderApp.swift              # @main, app lifecycle
│   ├── AppDelegate.swift           # NSApplicationDelegate for system integration
│   └── CiderPanel.swift            # NSPanel subclass for the sidebar window
├── Views/
│   ├── SidebarView.swift           # Root SwiftUI view, composes all components
│   ├── PinnedAppsView.swift        # Dock replacement grid
│   ├── WindowListView.swift        # Window tree view
│   ├── StatusBarView.swift         # (stub for future)
│   ├── ClipboardView.swift         # (stub for future)
│   ├── DropZoneView.swift          # (stub for future)
│   └── LauncherView.swift          # (stub for future)
├── ViewModels/
│   ├── SidebarViewModel.swift      # Hover state, layout management
│   ├── PinnedAppsViewModel.swift   # Pinned app list, launch logic
│   └── WindowListViewModel.swift   # Window enumeration, focus/close
├── Services/
│   ├── WindowManager.swift         # AXUIElement + CGWindowList wrapper
│   ├── AppLauncher.swift           # NSWorkspace app launching
│   ├── DockManager.swift           # Hide/restore system Dock
│   ├── ClipboardManager.swift      # (stub for future)
│   ├── LauncherEngine.swift        # (stub for future)
│   └── SystemStatus.swift          # (stub for future)
├── Models/
│   ├── WindowInfo.swift            # Window metadata
│   ├── AppInfo.swift               # App metadata (name, icon, bundleID, path)
│   └── CiderConfig.swift           # User preferences/settings
├── Utilities/
│   ├── AccessibilityHelpers.swift  # AXUIElement convenience wrappers
│   ├── Shell.swift                 # Shell command execution
│   └── Constants.swift             # Sizes, animation durations, defaults
├── Extensions/                     # (empty for now, future extension host)
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Cider.entitlements
```

### Key Technical Decisions

1. **NSPanel, not NSWindow** — The sidebar must float above other windows without taking focus. Use `NSPanel` with `.nonactivatingPanel` style mask and set `hidesOnDeactivate = false`, `canBecomeKey = false`, `level = .floating`.

2. **NSHostingView for SwiftUI** — Host SwiftUI views inside the NSPanel via `NSHostingView`. This gives you the best of both worlds: AppKit for system integration, SwiftUI for UI components.

3. **Accessibility API permission** — The app MUST request and check Accessibility permissions on first launch. Without this, window management cannot work. Use `AXIsProcessTrusted()` to check, and guide the user to System Settings > Privacy & Security > Accessibility if needed.

4. **Combine for reactive updates** — Use `@Published` properties in ViewModels and Combine publishers for window list changes, clipboard updates, etc.

5. **NSVisualEffectView for glassmorphism** — Wrap the sidebar content in `NSVisualEffectView` with material `.hudWindow` or `.popover` and blending mode `.behindWindow` for the native frosted glass effect.

6. **App icon rendering** — Use `NSWorkspace.shared.icon(forFile:)` to get app icons. For squircle shape, use `.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))`.

7. **Window enumeration** — Use `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` to get the window list. Filter out Cider's own windows. Map to `WindowInfo` model structs.

8. **Window focusing** — To focus a window: get the owning app's PID, create an `AXUIElementCreateApplication(pid)`, get the windows array, find the matching window, call `AXUIElementPerformAction(window, kAXRaiseAction)` and activate the app via `NSRunningApplication.activate()`.

9. **Persisting pinned apps** — Store as an array of bundle identifiers in UserDefaults or a JSON file at `~/Library/Application Support/Cider/config.json`.

10. **Menu bar icon** — Add an `NSStatusItem` in the menu bar as a secondary access point. Clicking it could toggle sidebar visibility. This also provides a place for settings and quit.

### Design Tokens

```swift
enum CiderDesign {
    static let sidebarWidthCollapsed: CGFloat = 72
    static let sidebarWidthExpanded: CGFloat = 280
    static let cornerRadius: CGFloat = 16
    static let componentSpacing: CGFloat = 8
    static let iconSize: CGFloat = 44
    static let iconCornerRadius: CGFloat = 12
    static let animationDuration: Double = 0.3
    static let hoverExpandWeight: CGFloat = 2.5
    static let hoverContractWeight: CGFloat = 0.5
    
    // Colors (amber/gold cider palette)
    static let accentColor = Color(hex: "#f59e0b")      // Amber
    static let accentLight = Color(hex: "#fcd34d")       // Light gold
    static let accentDark = Color(hex: "#d97706")        // Dark amber
    static let runningIndicator = Color(hex: "#22c55e")  // Green dot for running apps
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)
    static let separator = Color.white.opacity(0.1)
}
```

---

## What "Done" Looks Like for v0.1

When finished, I should be able to:

1. Launch Cider and see a floating glass sidebar on the left edge of my screen
2. The sidebar shows my pinned apps as squircle icons and a tree list of all open windows grouped by app
3. I can click a pinned app icon to launch or focus it
4. I can click any window in the list to bring it to the front
5. I can hover over the pinned apps section and it smoothly expands while the windows section contracts, and vice versa
6. Running apps show a green dot indicator
7. There's a menu bar icon I can click to toggle visibility or quit
8. The sidebar doesn't steal focus from whatever app I'm working in
9. The sidebar has the native macOS frosted glass appearance
10. I can right-click a pinned app to remove it

---

## Important Notes

- This is a real project that will be actively developed. Write clean, well-organized code with proper separation of concerns.
- Use Swift conventions: protocols for services, structs for models, classes for ViewModels with ObservableObject.
- Add TODO comments where future features will plug in, referencing the component name (e.g., `// TODO: ClipboardView will go here`).
- The extension system is important to the long-term architecture. Keep components modular so they could eventually become the "built-in extensions" pattern.
- Don't over-engineer the v0.1 — keep it simple and working. But don't create technical debt that makes the v0.2–v1.0 features hard to add.
- Include the Accessibility permission check and user guidance on first launch — without it, the app is useless.
- Test on a multi-monitor setup if possible — even for v0.1, the sidebar should at least work correctly on the primary display.
