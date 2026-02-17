# Cider - Claude Context Guide

Cider is a native macOS **floating panel** app for capturing and organizing bookmarks, notes, and projects. Activated by double-tapping Option, it provides a persistent workspace panel with tabbed content, a universal folder sidebar, and inline search. Uses SwiftUI + AppKit, targets macOS 14+.

## Critical Rules (Always Follow)

- **Never steal focus** - All floating surfaces use `NSPanel` with `.nonactivatingPanel`
- **No hardcoded colors** - Use `CiderColors.*` tokens from Constants.swift
- **No hardcoded fonts** - Use `CiderFont.*` tokens from CiderFont.swift (no `.font(.body)`, `.font(.caption)`, etc.)
- **No magic numbers** - Use spacing/animation tokens from Constants.swift
- **Spring animations only** - No `.easeIn`, `.easeOut`, `.linear` for UI motion
- **Respect Reduce Motion** - Every `withAnimation` and `.animation()` must use `reduceMotion ? .none : .spring`
- **Acrylic style** - Use `NSVisualEffectView` with `.underWindowBackground`, NOT `.glassEffect()`

## Primary Interface: Floating Panel

The floating panel is the main way users interact with Cider:
- **Activation:** Double-tap Option key
- **Opens on:** Screen where mouse is located
- **Style:** Dark acrylic with custom shadows, resizable from all edges
- **Tabs:** Home, Bookmarks, Notes (fixed tabs in title bar)
- **Sidebar:** Full-height floating column for folders & projects (organization only — no "All Items"). Traffic lights + view options in sidebar header. Auto-hides at compact widths.
- **Title bar:** Sidebar toggle + tab bar + capture button. Right-click context menu for window controls.
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

### For Display Issues or Performance Problems
**Read:** `Docs/TROUBLESHOOTING.md`
- Card sizing and masonry layout fixes
- Width pressure and panel resize issues
- Thumbnail rendering patterns
- CPU/performance fixes (filesystem watcher loops, view switching)

### Before Release
**Read:** `Docs/RELEASE_CHECKLIST.md` - QA verification

## Quick Reference

### Design Token Files
```
CiderColors  → Utilities/Constants.swift   (color palette)
CiderFont    → Utilities/CiderFont.swift   (typography)
Spacing      → Utilities/Constants.swift   (spacing scale)
Radius       → Utilities/Constants.swift   (corner radii)
ButtonStyles → Utilities/ButtonStyles.swift (pill button styles)
ContainerStyles → Utilities/ContainerStyles.swift (.sectionContainer, .cardContainer)
HoverState   → Utilities/HoverState.swift  (.hoverState modifier)
```

### Strict Build Check
```
swift build -Xswiftc -warnings-as-errors
```
Normal `swift build` hides deprecation warnings and unused-result diagnostics. Use strict mode to verify clean hygiene.

### Spacing Tokens
```
hairline: 1pt | xxs: 2pt | xs: 4pt | sm: 8pt | md: 12pt | lg: 16pt | xl: 20pt | xxl: 24pt | xxxl: 32pt
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
├── Models/           # Data models (Bookmark, Note, Folder, Project, CiderConfig, CiderTab, LibraryDisplayMode)
├── Services/         # Business logic (DoubleTapDetector, BookmarksStorage, NotesStorage, etc.)
├── Utilities/        # Constants, CiderFont, CiderColors, ButtonStyles, ContainerStyles, HoverState, helpers
├── ViewModels/       # ObservableObject view models (BookmarksViewModel, NotesViewModel, SettingsViewModel)
└── Views/
    ├── Bookmarks/         # Bookmark browser, cards (BookmarkCard, BookmarkListRow), masonry layout, panel view
    ├── Home/              # Home dashboard (Continue section + Library feed)
    ├── Notes/             # Notes editor, tab content, panel view
    ├── Projects/          # Project tab content
    ├── Search/            # Search palette and tab content
    ├── Settings/          # Settings views (General, About)
    └── Shared/            # Reusable: CiderTabBar, FolderSidebarView, ViewOptionsDropdown, etc.
```

## Panel Structure
```
CiderPanelView
├── HStack(spacing: 0)
│   ├── sidebarColumn (floating rounded-rect, full panel height)
│   │   ├── sidebarHeader (traffic lights + collapse toggle, top-aligned)
│   │   ├── FolderSidebarView(showBackground: false)
│   │   │   ├── Search field (top aligned with divider line)
│   │   │   ├── Folders section (hierarchical tree)
│   │   │   └── Projects section
│   │   └── sidebarFooter (gear + "New" pill menu + view options)
│   └── VStack (right column, top padding aligns title bar center with traffic lights)
│       ├── titleBar (animated sidebar toggle + CiderTabBar + capture button)
│       ├── Divider (14pt horizontal inset, aligned with card content edges)
│       └── contentArea (switches by selectedTab)
│           ├── HomeDashboardView (Continue section + Library feed, filters by folder)
│           ├── BookmarksTabContent → BookmarksBrowserView
│           └── NotesTabContent → NotesBrowserView
├── compactOverlaySidebar (< 680pt, slides over content)
├── SearchPaletteView (overlay)
└── PanelEdgeResizeView (all-edge resize handles)
```

## Panel Layout Alignment Rules

**Sidebar is the source of truth** for panel layout. When aligning elements between columns, match the right column to the sidebar — never move the sidebar to match the tabs.

- **Tab content padding:** 12pt (Spacing.md) at TabContent level + 2pt (Spacing.xxs) at BrowserView level = 14pt total. Applied OUTSIDE the ScrollView. See `Docs/DESIGN_SYSTEM.md` §4.1.
- **Divider inset:** `Spacing.md + Spacing.xxs` (14pt) — matches card content edges exactly.
- **Traffic lights:** sidebarHeader uses `HStack(alignment: .top)` + `.frame(height:, alignment: .top)` so lights stay pinned regardless of conditional content.
- **View options button:** frame height = `trafficLightTapTarget` (16pt), not `buttonTapTarget` (28pt), to center with traffic lights.
- **Search bar:** FolderSidebarView has no top padding — search bar top aligns with the divider line.
- **Right column top padding:** `Spacing.sm - 1` (7pt) so title bar center aligns with traffic light circle center.

## Bookmark Display Modes
```
BookmarkDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via CardSizing struct
- Interpolates between 4 stops: compact → comfortable → large → extraLarge
- Grid: fixed thumbnail height, proportional to card width
- Masonry: thumbnail height = exact image aspect ratio (no clamping)
- List: thumbnail width/height scale with slider

View options: Dropdown popover in sidebar header (ViewOptionsDropdown.swift)
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

## Home Display Modes
```
LibraryDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via LibraryCardSizing struct
- Delegates to CardSizing (bookmarks) and NoteCardSizing (notes)
- Mixed content: BookmarkCard/BookmarkListRow + NoteCardView/NoteListRow
- Continue section: sticky 8-item recents, two-column, collapsible
- Library feed: scrollable mixed feed, filters by folder selection

State: CiderPanelView owns @State, passes Bindings to HomeDashboardView
Persistence: homeDisplayMode + homeCardSizeScale on CiderConfig
```

## TipTap Editor Architecture

The notes editor uses a TipTap/ProseMirror instance inside a WKWebView.

- **Singleton WebView** — `NotesViewModel` owns the WKWebView (created via `ensureEditorWebView()`). `TipTapEditorView` is a thin NSView container that borrows it. Only one surface displays the editor at a time; the WebView moves between containers.
- **Coordinator** — `TipTapEditorCoordinator` handles JS→Swift message routing. Owned by the ViewModel, not by SwiftUI.
- **Editor resources** — `Resources/TipTapEditor/editor.html` + `editor.css` + `editor.js` (minified bundle)
- **CSS gotcha** — `line-height` on `<pre>` (block) controls code block spacing, NOT on `<code>` (inline child). The `<pre>` inherits body's `line-height` if not explicitly set.
- **Table CSS** — `width:auto; table-layout:auto` for content-sized tables (not `width:100%` which stretches to fill)
- **Accepted risk:** `allowingReadAccessTo` is filesystem root (`/`) so the editor can load images from any local path the user drags in. Navigation delegate filters external URLs. This is appropriate for a local-only desktop app with bundled editor HTML and ProseMirror schema validation.

## SwiftUI + NSPanel Gotchas

- **Animated content clipping:** Content with slide transitions (`.move(edge:)`) must have `.clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))` — otherwise animations overflow into the shadow area drawn by `AcrylicPanelBackground`. The shadow sits underneath in the ZStack and is unaffected by clipping the content layers above it.
- **VisualEffectView in overlays:** Use `.withinWindow` blending (not `.behindWindow`) for views overlaying the panel's own content. Our window background is `.clear` for custom shadows, so `.behindWindow` samples the desktop wallpaper. Only `AcrylicPanelBackground` should use `.behindWindow`.
- **Context menus:** Never use SwiftUI `.contextMenu` in lazy containers — it caches content and goes stale after data changes. Use the shared `CardContextMenu` (`Utilities/CardContextMenu.swift`) which builds a fresh native `NSMenu` on every right-click.
- **NSView overlays:** When overlaying `NSViewRepresentable`, override `hitTest` to return `nil` for non-target events — otherwise the overlay blocks left clicks, hovers, and drags from reaching SwiftUI content underneath.
- **@FocusState in NSPanel:** Non-activating panels need a delay before focus takes effect — use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }`
- **Card data refresh:** Use `.task(id: note.modifiedAt)` not `.task(id: note.id)` so card data reloads after edits
- **Text concatenation:** `Text("a") + Text("b")` is deprecated in macOS 26. Use `Text(AttributedString)` with per-range attributes instead.
- **Compact mode GeometryReader:** Measure panel width (HStack), NOT content area width. Content width changes when sidebar toggles, causing infinite collapse/expand feedback loop. Panel width is stable.
- **SourceKit false positives:** "Cannot find 'CiderFont' in scope" (and similar cross-file type errors) are SourceKit indexing noise, not real build errors. Ignore them — verify with `swift build` instead.
- **Shadow shapes use literal `Color.black`** — this is correct, not a CiderColors violation. The custom shadow pattern (blurred black RoundedRectangle) is intentional.
- **AppKit Reduce Motion:** For `NSAnimationContext` code (panel collapse), check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — `@Environment(\.accessibilityReduceMotion)` is SwiftUI-only.
- **CiderFont scale-dependent tokens:** `heroDisplay(scale:)` requires a `CGFloat` parameter — use `CiderFont.heroDisplay(scale: 1.0)`, not `CiderFont.heroDisplay`.
- **ScrollView bottom padding:** Padding on content INSIDE a ScrollView doesn't prevent clipping at the panel edge — the scroll area itself still extends to the edge. Put bottom padding OUTSIDE the ScrollView (on the ScrollView itself) so the scroll area is inset from the panel.
- **MasonryLayout cache:** `computeFrames` intentionally has NO width-only cache optimization. Subview sizes can change independently (e.g., `BookmarkCard.@State cardWidth` updating via GeometryReader after initial layout). Always recompute when SwiftUI calls layout methods.
- **Prefer inline GeometryReader over PreferenceKey:** `onPreferenceChange` fires with the `defaultValue` (often `0`) before the real measurement arrives, causing incorrect initial state. Inline `GeometryReader { proxy in let x = proxy.size.width ... }` is simpler and avoids this race.
- **GeometryReader threshold anti-oscillation:** When a threshold controls layout (e.g., 1 vs 2 columns), set it high enough that sidebar show/hide (~200pt delta) can't flip the result. Otherwise content width jumps when sidebar toggles, causing column flicker.
