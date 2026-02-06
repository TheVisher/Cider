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
- Search bar at top (filtering not yet wired)
- Pinned apps row — horizontal dock replacement
- Window list — grouped by app
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
- Type to enter query (filtering not yet wired)
- Clear button to reset search

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
- Folder creation/persistence is scaffolded but not yet wired in UI

**Settings:**
- Add/remove pinned apps
- Import apps from Dock
- Reorder by dragging

---

### 3. Window List

**What it replaces:** Stage Manager, ⌘Tab, App Exposé

**Features:**
- Grouped by app
- Collapse/expand apps
- Window title with app icon

**Window Actions (on hover):**
- Minimize button (−)
- Close button (×)

**Context Menu:**
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
- Double-tap Option to open (toggle)
- Double-tap speed (slider, not yet wired)

### Appearance Tab
- Text size (Small, Medium, Large)
- Palette size (Small, Medium, Large)
- Show menu bar icon toggle

### Advanced Tab
- Auto-hide apps toggle (Stage Manager-like behavior)
- Reset to defaults button

---

## Global Behaviors

### Activation

**Double-tap detection:**
- Modifier key: Option (configurable later)
- Tap twice within 300ms to toggle palette
- Both global (other apps focused) and local (Cider focused) event monitoring

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
| Option × 2 | Toggle palette |
| ⎋ | Close palette |

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
class CommandPalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
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
│   └── SettingsWindow.swift
├── Views/
│   ├── CommandPalette/
│   │   ├── CommandPaletteView.swift
│   │   ├── PaletteBackgroundView.swift
│   │   ├── PaletteSearchBar.swift
│   │   ├── PaletteAppsRow.swift
│   │   ├── PaletteContentArea.swift
│   │   └── PaletteFooterBar.swift
│   └── Settings/
│       └── SettingsView.swift
├── ViewModels/
│   ├── CommandPaletteViewModel.swift
│   ├── PinnedAppsViewModel.swift
│   └── WindowListViewModel.swift
├── Services/
│   ├── WindowManager.swift
│   ├── MonitorManager.swift
│   ├── DoubleTapDetector.swift
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
- [ ] Drag to reorder pinned apps
- [ ] Window tiling (left half, right half)
- [ ] Keyboard navigation

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
