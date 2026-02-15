# Cider Ideas & Feature Backlog

This document captures all feature ideas, enhancements, and polish items for Cider. Features are organized by category and will be prioritized based on which foundational systems they depend on.

> **Legacy note:** This backlog was written early in development. Some items may reference outdated UI concepts — interpret everything as command palette features.

---

## Categories

1. [Dock Replacement](#1-dock-replacement)
2. [Window Management (Stage Manager Replacement)](#2-window-management-stage-manager-replacement)
3. [Window Tiling](#3-window-tiling)
4. [App/Window Switching](#4-appwindow-switching)
5. [Multi-Monitor](#5-multi-monitor)
6. [Workspaces & Loadouts](#6-workspaces--loadouts)
7. [UI Layout Options](#7-ui-layout-options)
8. [Media & Audio](#8-media--audio)
9. [Search & Navigation](#9-search--navigation)
10. [Peek & Preview](#10-peek--preview)
11. [File Management (Drop Zone)](#11-file-management-drop-zone)
12. [Clipboard](#12-clipboard)
13. [Notifications](#13-notifications)
14. [Polish & Micro-interactions](#14-polish--micro-interactions)
15. [Keyboard & Power User](#15-keyboard--power-user)
16. [Accessibility](#16-accessibility)
17. [Onboarding & Setup](#17-onboarding--setup)
18. [Error Handling & Recovery](#18-error-handling--recovery)
19. [Notes & Companion Windows](#19-notes--companion-windows)
20. [Future / Long-term](#20-future--long-term)

---

## 1. Dock Replacement

### Currently Planned
- [x] Squircle app icons in grid layout
- [x] Running indicator (colored bar beneath icon, color extracted from app icon)
- [x] Drag to reorder pinned apps
- [x] Right-click context menu (Open, Quit, Show in Finder)
- [ ] Drop files onto app icon to open with that app
- [x] Folder support (group apps into collapsible folders)
- [ ] Badge support for notification counts
- [x] Import current Dock apps during setup

### New Ideas
- [ ] **App picker for adding apps** - "Add app" button opens picker showing /Applications with search
- [ ] **Drag and drop to add apps** - Drag from Finder into palette to pin
- [ ] **Auto-add newly installed apps** (setting) - Watch /Applications for changes, optionally auto-add
- [ ] **Smart suggestions** - "You opened Slack 12x this week but it's not in Cider. Add it?"
- [ ] **Recent apps section** - Show last 3-5 launched apps that aren't pinned
- [ ] **Double-click app icon = show all windows** - App Exposé style, spread all windows for that app

---

## 2. Window Management (Stage Manager Replacement)

### Currently Planned
- [x] Tree view: Apps → Windows (grouped by monitor then app)
- [x] Collapse/expand individual apps
- [x] Click window to focus (hides other apps when auto-hide enabled)
- [ ] Live preview thumbnails on hover
- [x] Window controls on hover: minimize, close
- [ ] Drag windows onto each other to create groups
- [ ] Window groups show as nested items, can be named
- [ ] "Minimize All", "Tile All" bulk actions

### New Ideas
- [x] **Close window without focusing** - X button works on background windows directly
- [ ] **Minimize all for specific app** - One click to sweep all Finder windows away
- [ ] **Restore all for specific app** - Bring back all minimized windows for an app
- [ ] **App-level context menu** - Right-click app header: Quit, Hide, Minimize All, Tile All, New Window
- [ ] **"Not responding" indicator** - Gray out thumbnail, show spinner for frozen apps
- [ ] **Last focused indicator** - Subtle highlight on the window you were just in
- [ ] **Window pinning** - Mark a window as "always visible" so it doesn't hide when focusing other apps
- [ ] **Quick rename window groups** - Name groups ("Research", "Comms") for identification

---

## 3. Window Tiling

### Currently Planned
- [ ] Context menu tiling: Left Half, Right Half, Top Half, Bottom Half, Quarters, Maximize, Center, Restore
- [ ] Implementation via AXUIElement position/size setting

### New Ideas
- [ ] **Dynamic tiling (shared edges)** - Windows aware of each other; drag one edge, adjacent windows resize together
- [ ] **Auto-fill on minimize** - When one tiled window minimizes, adjacent windows expand to fill the space
- [ ] **Tile groups persist** - Windows remember they're tiled together, respond as a unit
- [ ] **Drag thumbnail to screen position** - Drag from palette, drop anywhere on screen to position window there
- [ ] **Drag to edge for quick tile** - Drag window thumbnail toward screen edge to snap to that half
- [ ] **Visual indicator of tile state** - Badge or icon showing if window is tiled and where (left half, etc.)
- [ ] **Multi-select tiling** - Shift+click multiple windows, see overlay with zones, drag each to a zone, adjust borders, apply
- [ ] **Spring-loaded tile zones** - Drag window toward screen edge, shows preview of where it will tile

---

## 4. App/Window Switching

### Currently Planned
- [ ] ⌘K opens launcher
- [ ] ⌘⌥D toggles palette visibility
- [ ] ⌘⌥1-9 launches pinned app by position

### New Ideas
- [ ] **Cmd+Space opens Cider** - Main trigger for full UI
- [ ] **Cmd+Tab tap = quick swap** - Instantly switch to last window, no UI shown
- [ ] **Cmd+Tab hold = show UI** - After ~300ms, Cider appears for navigation
- [x] **Arrow key navigation** - When Cider is open, arrow keys move through window list
- [ ] **Horizontal layout for centered view** - Apps arranged left-to-right, windows cascade below each app
- [x] **↑↓ cycles windows within app** - Vertical arrows navigate the window list
- [ ] **←→ cycles between apps** - In centered view, horizontal arrows move between apps
- [x] **Enter to focus, Esc to dismiss** - Standard keyboard interaction
- [ ] **Release Cmd to confirm** - While holding Cmd+Tab, release to switch to highlighted window
- [x] **Type-to-filter** - Just start typing to filter the window list

---

## 5. Multi-Monitor

### Currently Planned
- [x] Windows grouped by monitor in palette
- [x] Drag windows between monitor groups to move them
- [ ] Keyboard shortcuts: ⌃⌥← / ⌃⌥→ to send window to left/right monitor

### New Ideas
- [ ] **"Move all to this monitor" button** - On each monitor header, one click moves all windows from other monitors here
- [ ] **Option+click = move all except focused** - Move everything but keep current window where it is
- [ ] **Drag monitor header onto another** - Move all windows between monitors
- [ ] **Remember palette position per monitor** - If monitor disconnects, gracefully move to primary
- [ ] **Restore layout when monitor reconnects** - Offer to put windows back where they were
- [ ] **Mini monitor icons** - Visual indicator showing which monitor is which
- [ ] **Rescue off-screen windows** - If window is on disconnected monitor, show "rescue" option to bring it back

---

## 6. Workspaces & Loadouts

### New Ideas (not in current docs)
- [ ] **Save current layout as loadout** - Capture which apps are open, window positions, which monitor
- [ ] **Restore loadout with one click** - Launch all apps, wait for windows, position them
- [ ] **Loadouts section in palette** - Quick access to saved workspaces
- [ ] **Named loadouts** - "Deep Work", "Communication", "Morning Setup", etc.
- [ ] **Loadout includes tile relationships** - If windows were dynamically tiled, restore that relationship
- [ ] **Auto-save last layout on quit** - Option to restore previous session on launch
- [ ] **Per-app window position memory** - Finder always opens on right, Terminal on left (learned over time)
- [ ] **Suggest grouping frequently paired apps** - "You always use Chrome + Notes together. Create a loadout?"

---

## 7. UI Layout Options

### New Ideas (not in current docs)
- [ ] **Centered layout: horizontal app arrangement** - Apps left-to-right in recency order
- [ ] **Windows cascade under each app** - Shows all windows/tabs for each app below its icon
- [ ] **Consistent keyboard nav** - Arrow keys work adapted to layout direction

---

## 8. Media & Audio

### New Ideas
- [ ] **Audio source indicator** - Icon on window/app that's currently outputting audio
- [ ] **Now Playing mini-player** - Collapsible section showing current track, artist, album art
- [ ] **Playback controls** - Play/pause, skip forward/back, scrubber
- [ ] **Works with any audio source** - Spotify, Apple Music, YouTube in browser, etc. (via macOS Now Playing)
- [ ] **Quick mute from Cider** - Mute a specific app's audio without focusing it

---

## 9. Search & Navigation

### New Ideas
- [x] **Always-visible search field** - At top of palette, type to filter instantly
- [x] **Search window titles** - Filter by what's in the window title
- [x] **Search app names** - Filter by app
- [ ] **Search browser tabs** - If browser integration exists, search tab titles too
- [ ] **Fuzzy matching** - "chr doc" matches "Chrome - Google Docs"
- [x] **Search in centered modal** - Just start typing, filters in real-time
- [ ] **Recent searches** - Quick access to previous filters

---

## 10. Peek & Preview

### New Ideas
- [ ] **Peek on hover hold** - Hover thumbnail for ~500ms, window floats to front temporarily
- [ ] **Other windows dim** - While peeking, other windows dim slightly for focus
- [ ] **Scroll while peeking** - Can scroll the peeked window without committing focus
- [ ] **Click to commit** - Click while peeking to actually focus the window
- [ ] **Move away to dismiss** - Mouse away and everything returns to previous state
- [ ] **Peek is read-only inspection** - Check info without context switching
- [ ] **Subtle border glow on peeked window** - Visual indicator of which window is being previewed
- [ ] **Highlight window position on hover** - When hovering thumbnail, show where that window is on screen

---

## 11. File Management (Drop Zone)

### Currently Planned
- [ ] Visual drop target for files
- [ ] Staged files persist until cleared
- [ ] Drag files out to any app or folder
- [ ] Multi-file support
- [ ] Clear all / individual remove buttons
- [ ] Shows file icon and name
- [ ] Spring-loaded: hover over app while dragging to open that app

### New Ideas
- [ ] **Drop zone always visible** - Persistent section at bottom of palette
- [ ] **Drag file over palette, it expands** - Auto-reveal on drag approach
- [ ] **File count badge** - Show how many files are staged
- [ ] **Sort staged files** - By name, date added, type
- [ ] **Quick Look integration** - Spacebar on staged file shows Quick Look preview

---

## 12. Clipboard

### Currently Planned
- [ ] Current clipboard preview
- [ ] History (last 20-50 items, configurable)
- [ ] Click item to copy back to clipboard
- [ ] Filter by type: text, images, files
- [ ] Pin important items
- [ ] Clear history
- [ ] Sensitive content detection (optional: don't store passwords)

### New Ideas
- [ ] **Always show current clipboard** - Small preview at bottom of palette
- [ ] **Expand for full history** - Click to see all clipboard items
- [ ] **Search clipboard history** - Filter by content
- [ ] **Clipboard and Drop Zone integration** - Unified "stuff I'm holding" concept

---

## 13. Notifications

### New Ideas
- [ ] **Badge counts on app icons** - Mirror Dock badges in Cider
- [ ] **Badge on running apps too** - Not just pinned, also in window list
- [ ] **Notification indicator on windows** - If a specific window has pending notification
- [ ] **Clear badges from Cider** - Mark as read without opening app

---

## 14. Polish & Micro-interactions

### Animations & Transitions
- [ ] Window thumbnails animate when reordering (not snap)
- [ ] App icon bounce/pulse on launch
- [ ] Closing window - thumbnail shrinks/fades out
- [ ] Expanding/collapsing sections with easing curves
- [ ] Dragged items have lift shadow
- [ ] Hover states fade in (not instant)

### Sounds (optional, off by default)
- [ ] Subtle click on window focus
- [ ] Soft whoosh on minimize all
- [ ] Gentle error sound for invalid actions
- [ ] Match macOS system sound scheme

### Haptics (for trackpad)
- [ ] Light tap when dropping into tile zone
- [ ] Feedback at edge of scrollable list
- [ ] Bump when drag-to-reorder snaps into place

### Visual Feedback
- [ ] Hover thumbnail = highlight actual window on screen with border pulse
- [ ] Running app dot has subtle breathing/pulse animation
- [ ] "Not responding" apps grayed out with spinner
- [ ] Selected items have subtle glow, not just background color

### Cursor & Pointer
- [ ] Enhanced shake-to-find cursor (larger max size, colored ring option)
- [ ] Hotkey trigger for cursor finder (for mouse users)
- [ ] Optional cursor trail when finding

---

## 15. Keyboard & Power User

- [x] **Full keyboard navigation** - Arrow keys, Enter to focus, Esc to dismiss, Delete to close
- [ ] **Option+click close = close all windows for that app**
- [ ] **Shift+click = multi-select windows** for bulk operations
- [ ] **Cmd+click = focus without hiding others** (override Stage Manager behavior)
- [ ] **Arrow keys wrap around** - Bottom of list → top
- [ ] **Type-to-select** - Start typing to highlight matching window
- [ ] **All shortcuts user-configurable**
- [ ] **Vim-style navigation option** - j/k instead of arrows

---

## 16. Accessibility

- [ ] **Respect Reduce Motion** - Disable bounces/animations
- [ ] **Respect Increase Contrast** - Adjust visual styling
- [ ] **Full VoiceOver support** - All palette elements accessible
- [ ] **Keyboard-only operation** - Everything possible without mouse
- [ ] **Screen reader announcements** - State changes announced properly

---

## 17. Onboarding & Setup

### First Launch Flow
- [ ] Welcome screen explaining concept
- [ ] Permission requests: Accessibility, Automation, Screen Recording (optional)
- [ ] "Replace Dock?" prompt with option to hide system Dock
- [ ] Set Dock auto-hide delay to maximum (effectively hidden)
- [ ] Store original Dock settings for restore
- [ ] Import current Dock apps
- [ ] Tutorial overlay highlighting components

### Settings
- [ ] **Auto-add newly installed apps** toggle
- [ ] **Suggest frequently used apps** toggle
- [ ] **Restore Dock settings** button

---

## 18. Error Handling & Recovery

- [ ] **Permission revoked handling** - Clear message with button to System Settings
- [ ] **App can't be focused** - Explain why (fullscreen on another desktop, etc.)
- [ ] **No generic errors** - Always explain what happened and what to do
- [ ] **Frozen app timeout** - Don't let frozen apps freeze Cider
- [ ] **Crash recovery** - Restore exact state on relaunch
- [ ] **Force quit removes immediately** - Don't wait for system, update UI instantly
- [ ] **Menu bar escape hatch** - "Restore Dock" always accessible even if Cider broken
- [ ] **Restore Dock on uninstall** - Put everything back

---

## 19. Notes & Companion Windows

*Lower priority - depends on core window management being solid first*

### Currently Planned (for later phases)
- [ ] Floating note window via hotkey
- [ ] Auto-save to local SQLite + markdown
- [ ] Basic tagging
- [ ] App association (auto-link to frontmost app)
- [ ] URL-linked notes
- [ ] Context restoration on app launch

### New Ideas
- [ ] Covered in main product spec, defer until v0.2+

---

## 20. Future / Long-term

*Ideas to capture but not prioritize yet*

- [ ] **Automation / scripting** - Trigger actions based on events
- [ ] **Extension system** - Third-party plugins
- [ ] **Sync across devices** - iCloud or other sync for settings/loadouts
- [ ] **Browser tab integration** - Show Chrome/Safari/Arc tabs as sub-items (requires extension or deep AX work)
- [ ] **LLM integration** - Voice-to-AI pipeline, summarization
- [ ] **Calendar companion** - Floating calendar window
- [ ] **OCR capture** - Screen region text extraction
- [ ] **Voice recorder + transcription**

---

## Priority Legend

When prioritizing, each feature should be tagged:

- **Foundation** - Core system this feature depends on (Dock, Window Management, Tiling, etc.)
- **Complexity** - Low / Medium / High
- **User Impact** - Low / Medium / High
- **Dependencies** - What must exist before this can be built

---

## Notes

- This document captures ideas from brainstorming sessions
- Features will be prioritized through interviews to determine importance
- Implementation order follows foundational dependencies, not just importance
- A feature rated "High importance" in Notes won't ship before Window Management is solid

---

*Last updated: February 2026*
