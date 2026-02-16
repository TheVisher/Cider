# Cider - Claude Context Guide

Cider is a native macOS **floating panel** app for capturing and organizing bookmarks, notes, and projects. Activated by double-tapping Option, it provides a persistent workspace panel with tabbed content, a universal folder sidebar, and inline search. Uses SwiftUI + AppKit, targets macOS 14+.

## Critical Rules (Always Follow)

- **Never steal focus** - All floating surfaces use `NSPanel` with `.nonactivatingPanel`
- **No hardcoded colors** - Use semantic system colors only
- **No magic numbers** - Use spacing/animation tokens from Constants.swift
- **Spring animations only** - No `.easeIn`, `.easeOut`, `.linear` for UI motion
- **Acrylic style** - Use `NSVisualEffectView` with `.underWindowBackground`, NOT `.glassEffect()`

## Primary Interface: Floating Panel

The floating panel is the main way users interact with Cider:
- **Activation:** Double-tap Option key
- **Opens on:** Screen where mouse is located
- **Style:** Dark acrylic with custom shadows, resizable from all edges
- **Tabs:** Home, Bookmarks, Notes (fixed tabs in title bar)
- **Sidebar:** Universal folder sidebar (auto-hides at compact widths)
- **Title bar:** Tab bar + contextual action buttons (capture, view options)
- **Dismissal:** Escape key, click outside, or double-tap Option again

## Documentation Reference

### Before Writing ANY UI Code
**Read:** `Docs/DESIGN_SYSTEM.md`
- Color palette, typography, spacing tokens
- Animation springs and transitions
- Component specifications

### For Acrylic/Material Implementation
**Read:** `Docs/ACRYLIC_STYLE.md`
- NSVisualEffectView patterns
- Custom shadow technique (blurred shapes, not .shadow())
- Border and divider guidelines
- NSPanel configuration

### Before Writing ANY Swift Code
**Read:** `Docs/CONVENTIONS.md`
- Swift style, file organization
- SwiftUI patterns, state management
- Performance guidelines, threading

### For Panel Architecture
**Read:** `Docs/FLOATING_PANEL.md`
- NSPanel patterns and configuration
- Panel positioning and resize handling
- CiderPanel implementation details

### For Swift 6.2 / Concurrency / Modern Patterns
**Read:** `Docs/TECH_STACK.md`
- Approachable Concurrency patterns
- ObservableObject + Combine state management
- UserDefaults + Codable storage

### When Adding a New Feature
**Read:** `Docs/SHARED_COMPONENTS.md`
- Check for reusable components and cross-tab patterns before building new ones
- If a new feature creates something reusable, add it to this doc
- Interview the user: could this component benefit other tabs?

**Read:** `Docs/USER_PREFERENCES.md`
- Settings patterns
- CiderConfig for persistent settings

### For Workspace / Folder Design
**Read:** `Docs/WORKSPACES_VISION.md` - Folders, projects, search vision
**Read:** `Docs/WORKSPACES_IMPLEMENTATION_PLAN.md` - Phased implementation

### For Tab-Specific Features & Ideas
Each tab has its own vision doc capturing features, roadmaps, and brainstorming. Always add tab-specific ideas to the relevant doc rather than general docs.
- **Home:** `Docs/HOME_VISION.md`
- **Bookmarks:** `Docs/BOOKMARKS_VISION.md`
- **Notes:** `Docs/NOTES_VISION.md`
- **Whiteboard:** `Docs/WHITEBOARD_VISION.md` (future tab)
- **Documents:** `Docs/DOCUMENTS_VISION.md` (future tab)
- **Books:** `Docs/BOOKS_VISION.md` (future tab)
- **Todos:** `Docs/TODOS_VISION.md` (future tab)

### For Bookmark Display Issues
**Read:** `Docs/TROUBLESHOOTING.md`
- Card sizing and masonry layout fixes
- Width pressure and panel resize issues
- Thumbnail rendering patterns

### Before Release
**Read:** `Docs/RELEASE_CHECKLIST.md` - QA verification

## Quick Reference

### Spacing Tokens
```
xxs: 2pt | xs: 4pt | sm: 8pt | md: 12pt | lg: 16pt | xl: 20pt | xxl: 24pt | xxxl: 32pt
```

### Animation Presets
```swift
.smooth       // spring(duration: 0.5, bounce: 0) - default transitions
.snappy       // spring(duration: 0.35, bounce: 0) - menus, popovers
.bouncy       // spring(duration: 0.5, bounce: 0.25) - UI feedback

// Custom springs (in CiderAnimation enum)
.hoverMagnify // spring(duration: 0.25, bounce: 0.05) - hover effects
.listReorder  // spring(duration: 0.3, bounce: 0.08) - drag-and-drop
```

### Corner Radii (always .continuous)
```
xs: 4pt | sm: 6pt | md: 10pt | lg: 14pt | xl: 20pt
```

### Key Patterns
```swift
// NSPanel setup (floating panel)
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
panel.backgroundColor = .clear
panel.hasShadow = false  // We draw custom shadows

// Acrylic background (NOT .glassEffect)
ZStack {
    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    Color.black.opacity(0.45)
    Color.white.opacity(0.03)
}

// Custom shadow as blurred shape
RoundedRectangle(cornerRadius: 14, style: .continuous)
    .fill(Color.black)
    .blur(radius: 18)
    .offset(y: 18)
    .opacity(0.7)

// Reduce Motion respect
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .spring()) { }
```

## File Structure
```
Sources/Cider/
├── App/              # Entry point, AppDelegate, Panels (CiderPanel, Bookmarks, Notes, Settings)
├── Models/           # Data models (Bookmark, Note, Folder, Project, CiderConfig, CiderTab)
├── Services/         # Business logic (DoubleTapDetector, BookmarksStorage, NotesStorage, etc.)
├── Utilities/        # Constants, extensions, helpers (HighlightedText, etc.)
├── ViewModels/       # ObservableObject view models (BookmarksViewModel, NotesViewModel, SettingsViewModel)
└── Views/
    ├── Bookmarks/         # Bookmark browser, cards, masonry layout, panel view
    ├── Home/              # Home dashboard
    ├── Notes/             # Notes editor, tab content, panel view
    ├── Projects/          # Project tab content
    ├── Search/            # Search palette and tab content
    ├── Settings/          # Settings views (General, Advanced, About)
    └── Shared/            # Reusable: CiderTabBar, FolderSidebarView, ViewOptionsDropdown, etc.
```

## Panel Structure
```
CiderPanelView
├── titleBar
│   ├── Sidebar toggle button
│   ├── CiderTabBar (Home, Bookmarks, Notes)
│   ├── Capture button (bookmarks tab only)
│   └── View options button + popover (bookmarks & notes tabs)
│       └── ViewOptionsDropdown (card size slider + view mode icons)
├── HStack
│   ├── FolderSidebarView (universal, auto-hides at compact width)
│   │   ├── Search field
│   │   ├── Folders section (hierarchical tree)
│   │   └── Projects section
│   └── Content area (switches by selectedTab)
│       ├── HomeDashboardView
│       ├── BookmarksTabContent → BookmarksBrowserView
│       └── NotesTabContent → NotesBrowserView
└── PanelEdgeResizeView (all-edge resize handles)
```

## Bookmark Display Modes
```
BookmarkDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via CardSizing struct
- Interpolates between 4 stops: compact → comfortable → large → extraLarge
- Grid: fixed thumbnail height, proportional to card width
- Masonry: thumbnail height = exact image aspect ratio (no clamping)
- List: thumbnail width/height scale with slider

View options: Dropdown popover in title bar (ViewOptionsDropdown.swift)
```

## Note Display Modes
```
NoteDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via NoteCardSizing struct
- Text-forward cards: wider min widths, side images instead of top images
- Images downsampled to 240px thumbnails via CGImageSource (not full NSImage)
- Card data (preview, word count, images) loaded async via NoteCardData.load()
- Sorted by persisted createdAt (stored in notes index, not filesystem)

ViewOptionsDropdown is generic over DisplayModeOption protocol
```

## SwiftUI + NSPanel Gotchas

- **Context menus:** Never use SwiftUI `.contextMenu` in lazy containers — it caches content and goes stale after data changes. Use the shared `CardContextMenu` (`Utilities/CardContextMenu.swift`) which builds a fresh native `NSMenu` on every right-click.
- **NSView overlays:** When overlaying `NSViewRepresentable`, override `hitTest` to return `nil` for non-target events — otherwise the overlay blocks left clicks, hovers, and drags from reaching SwiftUI content underneath.
- **@FocusState in NSPanel:** Non-activating panels need a delay before focus takes effect — use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }`
- **Card data refresh:** Use `.task(id: note.modifiedAt)` not `.task(id: note.id)` so card data reloads after edits
