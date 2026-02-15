# Cider — macOS Command Palette

## Product Vision

Cider replaces the Dock, Stage Manager, and window switching with a unified command palette. Double-tap Option, see all your windows and apps, click to focus. Simple, fast, native.

---

## Core Interface

### Command Palette

**Trigger:**
- Double-tap Option key (currently fixed to Option)
- Click menu bar icon

**Features:**
- Search bar at top — filters windows and apps in real-time
- Pinned apps row — horizontal dock replacement with folders
- Window list — grouped by monitor and app
- Window actions — close, minimize, move between monitors
- Auto-hide apps — focus one window, others move aside

**Behavior:**
- Appears on the screen where your mouse is
- Never steals focus from your active app
- Dismisses when you click a window or press Escape

---

## Components

### 1. Search Bar

**Features:**
- Search field at top (focused on open)
- Type to filter windows and apps in real-time (case-insensitive substring matching)
- Clear button to reset search
- Highlighted text shows matching portions in results

---

### 2. Pinned Apps Row

**What it replaces:** macOS Dock

**Features:**
- Horizontal row of app icons
- Running indicator — colored bar under running apps (color extracted from app icon)
- Hover to scale up (1.1×)
- Click to launch or focus
- Context menu:
  - Open
  - Quit (if running)
  - Show in Finder

**Folders:**
- Group apps into collapsible folders
- Mini 2×2 grid preview of folder contents
- Click folder to expand popup with all apps
- Folder creation/editing via settings or context menu
- Folders persist across launches (stored in UserDefaults)

**Settings:**
- Add/remove pinned apps
- Import apps from Dock
- Reorder by dragging

---

### 3. Window List

**What it replaces:** Stage Manager, ⌘Tab, App Exposé

**Features:**
- Grouped by monitor, then by app
- Collapse/expand apps
- Window title with app icon
- Drag windows between monitors
- Keyboard navigation (↑↓ to navigate, Enter to focus, Esc to dismiss)

**Window Actions (on hover):**
- Minimize button (−)
- Close button (×)

**Context Menu:**
- Focus Window
- Close Window
- Minimize Window
- Move to Monitor → [list of monitors]
- Quit [App Name]

**Data Source:**
- CGWindowListCopyWindowInfo for window enumeration
- AXUIElement for window manipulation

---

### 4. Footer

**Features:**
- Settings button — opens settings window
- Keyboard shortcut reminder

---

## Settings Window

### General Tab
- Launch at login toggle
- Activation mode (Double tap / Single tap)
- Option+Tab window cycling toggle
- Cycle all screens toggle

### Pinned Apps Tab
- Add/remove pinned apps
- Create/edit/delete app folders
- Import apps from Dock

### Appearance Tab
- Text size (Small, Medium, Large)
- Palette size (Small, Medium, Large)
- Show menu bar icon toggle

### Advanced Tab
- Auto-hide apps toggle (Stage Manager-like behavior)
- Remember palette state toggle
- Reset to defaults button

### About Tab
- App version information
- Credits

---

## Global Behaviors

### Activation

**Activation detection:**
- Modifier key: Option
- Mode: Double-tap (tap twice within 300ms) or Single-tap (configurable)
- Both global (other apps focused) and local (Cider focused) event monitoring

### Option+Tab Window Cycling
- Hold Option, tap Tab to cycle through open windows
- Release Option to focus the selected window
- Visual overlay shows the cycling state
- Configurable to cycle current screen only or all screens

### Multi-Monitor Support

- Palette opens on screen where mouse is located
- Palette groups windows by app
- Move windows between monitors via context menu

### Auto-Hide Apps

When enabled:
- Focusing a window hides other apps (like Stage Manager)
- Staged apps remain in the window list and are restored when focused

### Accessibility

- Respects Reduce Motion — replaces animations with 0.2s crossfades
- Respects Reduce Transparency — uses opaque backgrounds
- VoiceOver labels on all interactive elements

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Option × 2 | Toggle palette (double-tap mode) |
| Option × 1 | Toggle palette (single-tap mode) |
| ⎋ | Close palette |
| ↑ / ↓ | Navigate window list |
| ← / → | Navigate pinned apps / switch sections |
| ⏎ | Focus selected window or launch app |
| ⌥ + Tab | Cycle through windows |

---

## Setup Flow

### First Launch

**Planned (not yet implemented):**
1. Welcome screen explaining the concept
2. Permission requests:
   - **Accessibility** (required for window management)
   - Screen Recording (optional, for future window thumbnails)
3. Choose activation key
4. Import pinned apps from Dock (optional)
5. Tutorial highlighting components

### Permissions

| Permission | Why | When Requested |
|------------|-----|----------------|
| Accessibility | Window enumeration, focus, close, move | First launch |
| Screen Recording | Window preview thumbnails (future) | When enabling previews |

---

## Technical Architecture

### Core Framework

- **Language:** Swift
- **UI:** SwiftUI + AppKit
- **Panel:** NSPanel with .nonactivatingPanel

### Key Services

```
┌─────────────────────────────────────────────┐
│              Cider Command Palette           │
├─────────────────────────────────────────────┤
│  SwiftUI Views                              │
│  - CommandPaletteView                       │
│  - PaletteAppsRow                          │
│  - PaletteContentArea                      │
├─────────────────────────────────────────────┤
│  ViewModels                                 │
│  - CommandPaletteViewModel                 │
│  - WindowListViewModel                     │
├─────────────────────────────────────────────┤
│  Services                                   │
│  ┌─────────┬──────────┬──────────┐         │
│  │ Window  │ Monitor  │ DoubleTap│         │
│  │ Manager │ Manager  │ Detector │         │
│  ├─────────┼──────────┼──────────┤         │
│  │OptionTab│ Window   │ App      │         │
│  │ Detector│ Cycling  │ Launcher │         │
│  └─────────┴──────────┴──────────┘         │
├─────────────────────────────────────────────┤
│  System APIs                                │
│  ┌─────────┬──────────┬──────────┐         │
│  │ AX API  │CGWindow  │ NSEvent  │         │
│  │         │ List     │          │         │
│  └─────────┴──────────┴──────────┘         │
└─────────────────────────────────────────────┘
```

### NSPanel Configuration

```swift
final class CommandPalettePanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 500)
        super.init(
            contentRect: initialFrame,
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
        hasShadow = false  // We draw custom shadows

        isMovable = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }   // Allow text input
    override var canBecomeMain: Bool { false }
}
```

---

## File Structure

```
Cider/
├── App/
│   ├── CiderApp.swift
│   ├── AppDelegate.swift
│   ├── CommandPalettePanel.swift
│   ├── WindowCyclingPanel.swift
│   └── SettingsWindow.swift
├── Views/
│   ├── CommandPalette/
│   │   ├── CommandPaletteView.swift
│   │   ├── PaletteBackgroundView.swift
│   │   ├── PaletteSearchBar.swift
│   │   ├── PaletteAppsRow.swift
│   │   ├── PaletteContentArea.swift
│   │   └── PaletteFooterBar.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── GeneralSettingsView.swift
│   │   ├── AppearanceSettingsView.swift
│   │   ├── PinnedAppsSettingsView.swift
│   │   ├── AdvancedSettingsView.swift
│   │   └── AboutSettingsView.swift
│   ├── WindowCycling/
│   │   └── WindowCyclingOverlayView.swift
│   └── PinnedAppsView.swift
├── ViewModels/
│   ├── CommandPaletteViewModel.swift
│   ├── PinnedAppsViewModel.swift
│   ├── WindowListViewModel.swift
│   └── SettingsViewModel.swift
├── Services/
│   ├── WindowManager.swift
│   ├── MonitorManager.swift
│   ├── DoubleTapDetector.swift
│   ├── OptionTabDetector.swift
│   ├── WindowCyclingManager.swift
│   ├── AppLauncher.swift
│   ├── DockManager.swift
│   └── WindowPreviewService.swift
├── Models/
│   ├── WindowInfo.swift
│   ├── AppInfo.swift
│   ├── MonitorInfo.swift
│   └── CiderConfig.swift
└── Utilities/
    ├── Constants.swift
    ├── AccessibilityHelpers.swift
    ├── ColorExtractor.swift
    ├── HighlightedText.swift
    ├── PaletteFocusState.swift
    ├── Shell.swift
    └── VisualEffectView.swift
```

---

## Milestones

### v0.1 — MVP (Current)
- [x] Command palette shell with search field
- [x] Pinned apps row
- [x] Window list grouped by app
- [x] Double-tap activation
- [x] Settings window
- [x] Multi-monitor support

### v0.2 — Polish
- [ ] Window preview thumbnails
- [x] Drag to reorder pinned apps
- [x] Keyboard navigation (↑↓←→, Enter, Esc)
- [x] Search filtering of windows and apps
- [x] App folders in pinned apps row
- [x] Drag windows between monitors
- [x] Option+Tab window cycling

### v0.3 — Extensions
- [ ] Quick capture (notes, bookmarks)
- [ ] Clipboard history
- [ ] Timer overlay

### v1.0 — Public Release
- [ ] App Store submission
- [ ] Documentation
- [ ] Marketing website

---

## Design Language

Cider uses a **Raycast-inspired acrylic material**:

- Dark translucent background (`NSVisualEffectView` with `.underWindowBackground`)
- Custom shadows drawn as blurred shapes
- White borders at 25% opacity
- No Liquid Glass — intentional choice for cleaner, more predictable appearance

See `ACRYLIC_STYLE.md` for implementation details.
