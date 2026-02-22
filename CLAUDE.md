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
- **Tabs:** Home (only fixed tab) + user-created saved view tabs, search tabs, and external source tabs — all closeable
- **Sidebar:** Full-height floating column for folders and linked sources (organization only — no "All Items"). Traffic lights + view options in sidebar header. Auto-hides at compact widths.
- **Title bar:** Sidebar toggle + tab bar + capture button. Right-click context menu for window controls.
- **Dismissal:** Escape key (clears search first, then dismisses), click outside, or double-tap Option again

## Documentation Reference

### Full Docs Map
**Read:** `Docs/DOCS_INDEX.md` — lists every doc, what it covers, and its implementation status. Start here when you need to find, read, or update the right doc.

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

### For AI & Apple Intelligence Features
**Read:** `Docs/AI_VISION.md`
- Foundation Models (on-device LLM), NaturalLanguage, Vision framework integration
- Tiered AI strategy: no-AI → Apple on-device → cloud API (optional)
- Page summaries, auto-tagging, smart search, transcript summaries
- Core Spotlight indexing, App Intents / Shortcuts

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
├── App/              # Entry point, AppDelegate, Panels (CiderPanel, DetailPopover, Settings)
├── Models/           # Data models (Bookmark, Note, Folder, Project, CiderConfig, TrashItem, CiderTab, LibraryDisplayMode)
├── Services/         # Business logic (DoubleTapDetector, BookmarksStorage, NotesStorage, TrashStorage, CiderUndoManager, SpotlightIndexer, etc.)
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
│           ├── FolderDetailView (when folder selected — tab-independent, deselects tabs)
│           ├── HomeDashboardView (Continue section + Library feed)
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
- **Sidebar live search:** `FolderSidebarView` has a `searchText: Binding<String>` TextField (not a button). `CiderPanelView` owns `@State sidebarSearchText` (raw binding for instant TextField feedback) and `@State debouncedSearchText` (150ms debounce via `Task.sleep` with cancellation). Content views (HomeDashboardView, FolderDetailView, SavedViewTabContent) receive the debounced value. Cleared on tab/folder change. `SourceDetailView` does NOT support search yet.
- **Escape priority chain:** sidebarSearchText non-empty → clear search; else editor active → close editor; else selection → clear selection. Order matters — search clears first.
- **Right column top padding:** `Spacing.sm - 1` (7pt) so title bar center aligns with traffic light circle center.

## Bookmark Display Modes
```
BookmarkDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via CardSizing struct
- Interpolates between 4 stops: compact → comfortable → large → extraLarge
- Grid: fixed thumbnail height, proportional to card width
- Masonry: thumbnail height = exact image aspect ratio (no clamping)
- List: thumbnail width/height scale with slider
- Dual image assets per bookmark:
  - `.originals/` keeps full-size source image
  - `.thumbnails/` stores downsampled runtime PNG (currently max 720px)
  - Existing legacy thumbnails are normalized on load
- Async thumbnail loading: `.task(id: fingerprint)` + `Task.detached` + `CGImageSourceCreateWithURL` — never `NSImage(contentsOfFile:)` on main thread

View options: Dropdown popover in sidebar header (ViewOptionsDropdown.swift)
```

## Note Display Modes
```
NoteDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via NoteCardSizing struct
- Text-forward cards: wider min widths, side images instead of top images
- Images downsampled to 240px thumbnails via CGImageSource (not full NSImage)
- Card data (preview, word count, images) loaded async via NoteCardData.load()
- NoteCardData.load() calls resolvedContent once, passes to stripMarkup/countWords/imageURLs(from:) — never call resolvedContent multiple times
- Image URL regexes are static let on Note (compiled once, not per call)
- Sorted by persisted createdAt (stored in notes index, not filesystem)

ViewOptionsDropdown is generic over DisplayModeOption protocol
```

## Home Display Modes
```
LibraryDisplayMode: .list | .grid | .masonry

Card sizing: Continuous slider (0-3 scale) via LibraryCardSizing struct
- Delegates to CardSizing (bookmarks) and NoteCardSizing (notes)
- Mixed content: BookmarkCard/BookmarkListRow + NoteCardView/NoteListRow + DateCardCardView + ContactCardCardView
- Continue section: sticky 8-item recents, two-column, collapsible
- Library feed: scrollable mixed feed, filters by folder selection

LibraryItemV2 discriminated union: .bookmark(Bookmark) | .note(Note) | .dateCard(DateCard) | .contact(ContactCard)
- dateAnchor: Date? — key property for calendar projection; dateCards use startAt, contacts use birthday, bookmarks/notes nil
- isCompleted: Bool — only meaningful for dateCards; used by stack surfacing rules like pinUntilDone

LibraryViewModel — unified query engine reading from all 4 storages; rebuilds on any storage change
- Produces: filtered library feed, calendar buckets, stack resolutions
- Pre-computes `recentItems` (top 8 by updatedDate) during rebuildItems() — HomeDashboardView reads this directly, no O(N log N) sort in body
- `filteredItemsCache` memoizes the last filter+sort result — avoids re-filtering on unrelated body evaluations
- `matchesTextQuery` uses token-based matching: splits query on spaces, each token must match in at least one field via `localizedStandardContains` (diacritic- and case-insensitive, same as Finder)
- `externalFileContentCache` (static) caches external file disk reads during text search — cleared in `rebuildItems()`
- `NoteCardDataCache` (Note.swift) — cross-view cache for `NoteCardData`, keyed by `(noteID, modifiedAt)`. Used by `NoteCardView` and `NoteListRow` to avoid re-loading card data when scrolling/switching tabs.
- `NotesStorage.contentCache` — in-memory cache for note file content, keyed by `(noteID, modifiedAt)`. Avoids repeated disk reads during search. Invalidated in `save()`, `delete()`, `scanNotes()`.
- Stacks: CardStack has matchRules + manualItemRefs, resolves items dynamically (not containers)
- SavedViews: isTabPinned: Bool controls tab bar presence; calendar is a view mode toggle, not a separate tab

State: CiderPanelView owns @State, passes Bindings to HomeDashboardView
Persistence: homeDisplayMode + homeCardSizeScale on CiderConfig
```

## Search Architecture

Two search systems: **SearchService** (search palette / search tab) and **LibraryViewModel.matchesTextQuery** (sidebar live search / saved view filtering). Both use the same token-based matching pattern:
- Split query on spaces into tokens
- Each token must match in at least one field via `localizedStandardContains` (Apple's diacritic- and case-insensitive matching — same as Finder)
- Bookmarks search: title, URL, host, notes, tags
- Notes search: title + full file content (loaded via `NotesStorage.loadContent`, cached in-memory)
- Date cards: title, details, location
- Contacts: display name, relationship label, notes

**SearchService** also produces `SearchSnippet` (prefix/match/suffix with ellipsis) for body-only matches. Uses `extractSnippet(tokens:from:windowSize:)` to find the first matching token and return surrounding context.

**SpotlightIndexer** (`Services/SpotlightIndexer.swift`) indexes all items into Core Spotlight for system-wide search (Spotlight, Raycast, Alfred). Subscribes to storage `$published` properties with 2-second debounce. Gated by `CiderConfig.enableSpotlightIndexing`. Note: Core Spotlight requires a proper `.app` bundle — SPM executables silently fail to surface items. Indexing code is ready but dormant during development builds.

## Settings Architecture

Settings categories live in `SettingsCategory` enum. Adding a new top-level settings section requires: (1) new case in `SettingsCategory`, (2) add to `primaryCategories`, (3) new case(s) in `SettingsSubcategory`, (4) wire in `subcategories` switch and `selectedSubcategoryContent` switch. Current categories: General, Notes, Bookmarks, Appearance, Data, Advanced, About. Data subcategories: Directories (ciderDataDirectory + notesDirectory pickers), Trash (`StorageSettingsView`), Notifications (toast position pickers). Notes subcategories: Behavior, Editor. Bookmarks subcategory: Behavior (no directory picker — moved to Data → Directories). Deep-link string for "View Trash" undo toast is `"data"` (navigates to `.data` category).

## TipTap Editor Architecture

The notes editor uses a TipTap/ProseMirror instance inside a WKWebView.

- **Singleton WebView** — `NotesViewModel` owns the WKWebView (created via `ensureEditorWebView()`). `TipTapEditorView` is a thin NSView container that borrows it. Only one surface displays the editor at a time; the WebView moves between containers.
- **Coordinator** — `TipTapEditorCoordinator` handles JS→Swift message routing. Owned by the ViewModel, not by SwiftUI.
- **Editor resources** — `Resources/TipTapEditor/editor.html` + `editor.css` + `editor.js` (minified bundle)
- **CSS gotcha** — `line-height` on `<pre>` (block) controls code block spacing, NOT on `<code>` (inline child). The `<pre>` inherits body's `line-height` if not explicitly set.
- **Table CSS** — `width:auto; table-layout:auto` for content-sized tables (not `width:100%` which stretches to fill)
- **WebView access scope:** `allowingReadAccessTo` is set to `NSHomeDirectory()` — the editor can load images from any path under the user's home directory (notes, attachments, dragged images). Navigation policy is deny-by-default: only `file://` and `about:` are allowed; all other schemes are blocked regardless of how the navigation was triggered. User-clicked external links are opened in the system browser then cancelled.
- **Image serialization format:** `CiderImage.serialize` ALWAYS uses `<img src="..." alt="..." />` HTML — never `![]()` markdown. Reason: `![]()` inside a `<p style="text-align: ...">` block is treated as raw literal text by markdown-it (CommonMark type-6 HTML block rule). `<img>` is safe in both aligned and plain paragraphs; markdown-it wraps a bare `<img>` in `<p>` on reload and TipTap parses it back correctly. Don't revert to `![]()`.
- **CommonMark HTML block rule:** `<p>...</p>` (and other block-level HTML tags) are CommonMark type-6 HTML blocks — markdown-it does NOT parse markdown syntax inside them. So `<p style="text-align: center">![alt](src)</p>` renders the `![]()` as raw text, not an image. Always use `<img>` inside any `<p>` block.
- **Legacy note migration:** `normalizeIncomingMarkdown` calls `convertMarkdownImagesInHtmlParagraphs` (in `editor.js`) to convert any `<p>..![]()</p>` patterns to `<p>..<img /></p>` on load. One-time migration for old notes; the correct serialized format going forward is `<img>` everywhere.
- **TipTap normalization round-trip:** Pushing raw markdown via `pushContentToEditor` fires `contentChanged` with TipTap-serialized output that may differ from the input even with zero edits. When loading external files, set a flag (`isLoadingExternalFile`) and absorb the first `contentChanged` by updating `lastSyncedDiskContent` to the normalized value without writing to disk.
- **`syncExternalContentFromEditor` vs external files:** The async JS eval safety net exists to catch final keystrokes for native notes. For external files it causes spurious writes — the async eval path may serialize differently than `contentChanged`, bypassing equality guards. Use `editingContent` as authoritative for external files; do not call `syncExternalContentFromEditor` from `flushSave`.
- **External file mtime integrity:** Every save path (`contentChanged` debounce, `flushSave`, any async sync) must guard with `content != lastSyncedDiskContent` before writing. Opening and closing a file with no edits must never touch the filesystem.
- **Text-align lost on image paragraphs:** ProseMirror's DOMParser empirically fails to read `textAlign` from `<p style="text-align: center">` when the paragraph contains `<img>` with NodeViews. markdown-it preserves the HTML correctly — the loss happens during ProseMirror parse. Fix: `repairTextAlignAfterParse()` in `editor.js` — parses input HTML into DOM, walks ProseMirror doc in parallel, applies missing `textAlign` via `tr.setNodeMarkup()` with `addToHistory: false`. Do NOT set `preventUpdate` on the repair transaction — `contentChanged` must fire so `editingContent` gets the corrected content for save.
- **JS→Swift debugging:** WKWebView `console.log` does NOT appear in Xcode debug console. Use `postEditorDiagnostic(message)` which calls `window.webkit.messageHandlers.editorDiagnostic.postMessage()` → coordinator routes to `NSLog`. Remove all diagnostic calls before shipping.

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
- **CiderFont scale is cached:** `CiderFont._cachedScale` (`nonisolated(unsafe) static var`) is set at startup and refreshed by `CiderFont.invalidateScale()` at the top of `handleConfigChanged()`. Font tokens read the cached value — no UserDefaults decode per render. If you add a new config-driven font property, call `invalidateScale()` from `handleConfigChanged()`. Only `heroDisplay(scale:)` takes an explicit parameter; all other tokens respond automatically.
- **StoragePaths directory caching:** `cachedCiderDataDirectoryURL` and `notesDirectoryPath` are `nonisolated(unsafe) static var` caches that avoid `CiderConfig.load()` (UserDefaults decode) on every access. Invalidated by `StoragePaths.invalidateCachedDirectory()` in `handleConfigChanged()`. `Bookmark.thumbnailFileURL`/`originalImageFileURL` and `Note.resolvedContent`/`imageURLs` use these cached paths. Never call `CiderConfig.load()` in view body or computed properties that run during render — use cached paths or `@State config` instead.
- **ScrollView bottom padding:** Padding on content INSIDE a ScrollView doesn't prevent clipping at the panel edge — the scroll area itself still extends to the edge. Put bottom padding OUTSIDE the ScrollView (on the ScrollView itself) so the scroll area is inset from the panel.
- **MasonryLayout cache:** `computeFrames` has no width-only cache across layout passes — subview sizes can change independently (e.g., `BookmarkCard.@State cardWidth` updating via GeometryReader). However, `placeSubviews` skips recomputation when width matches `sizeThatFits` (safe within same layout pass). `sizeThatFits` always recomputes to catch subview size changes.
- **Prefer inline GeometryReader over PreferenceKey:** `onPreferenceChange` fires with the `defaultValue` (often `0`) before the real measurement arrives, causing incorrect initial state. Inline `GeometryReader { proxy in let x = proxy.size.width ... }` is simpler and avoids this race.
- **GeometryReader threshold anti-oscillation:** When a threshold controls layout (e.g., 1 vs 2 columns), set it high enough that sidebar show/hide (~200pt delta) can't flip the result. Otherwise content width jumps when sidebar toggles, causing column flicker.
- **Home tab kept alive:** `HomeDashboardView` is always in the view tree (ZStack with `opacity(isHomeActive ? 1 : 0)` + `allowsHitTesting`). Switching tabs doesn't destroy it — thumbnails, card data, and scroll position persist. Other tabs (saved views, search, external sources) still create/destroy on demand. `isHomeActive = selectedTab == .home && selectedFolderID == nil && selectedSourceID == nil`.
- **Folder view condition order:** In `tabContentBody`, check `selectedFolderID != nil` BEFORE the ZStack that contains Home — otherwise Home renders instead of FolderDetailView when a folder is selected on the Home tab.
- **Tab deselection in folder view:** CiderTabBar takes `selectedFolderID` binding. `isSelected = selectedTab == tab && selectedFolderID == nil`. Clicking a tab sets `selectedFolderID = nil` so re-clicking the same tab works to exit folder view.
- **Inline note editor:** Notes open inline within CiderPanelView via push/pop navigation (`editingNoteID` state). Editor takes over the content area; title bar swaps to back button + editable title + formatting controls. Escape or back button closes the editor, flushes save, and returns to the previous view.
- **onDrop concurrency:** `loadDataRepresentation` callbacks are non-isolated. Capture view model references locally before the closure, then do lookups inside `Task { @MainActor in }` to avoid main-actor-isolation warnings.
- **Escape key in NSPanel:** `.onExitCommand` does NOT work with `.nonactivatingPanel` — use a hidden `Button("") { ... }.keyboardShortcut(.escape, modifiers: [])` in `.background {}` instead.
- **Modifier detection in Button actions:** Use `NSEvent.modifierFlags` (static property) to check `.command` / `.shift` at click time. Works inside Button action closures without needing gesture composition.
- **Custom UTIs in `.onDrop`:** `hasItemConformingToTypeIdentifier()` and `registeredTypeIdentifiers.contains()` both fail for unregistered custom UTIs (e.g., `com.cider.multi-drag`). Encode payloads in `public.utf8-plain-text` with a distinctive prefix (e.g., `cider-multi-drag:JSON`) and detect via text parsing in drop handlers.
- **Drag preview clipping:** `scaleEffect`, `rotationEffect`, and `offset` on `.onDrag(preview:)` views push content outside the view's natural bounds. macOS clips the preview window to those bounds. Add explicit `.padding()` before transforms to prevent clipping.
- **Multi-drag provider types:** Don't register single-item type identifiers on multi-drag providers — the single-item drop handler fires first (by order in `handleFolderDrop`) and intercepts the drop, ignoring the multi-drag payload.
- **Shared view parameter changes:** `BookmarksBrowserView` is used by `CiderPanelView` (and potentially multiple call sites within it). When adding required parameters, update ALL call sites.
- **NSOpenPanel from non-activating panel:** Call `NSApp.activate(ignoringOtherApps: true)` before `runModal()` — otherwise the file picker sidebar isn't fully interactive (requires multiple clicks). Don't set `panel.level = .floating` on the open panel.
- **Mouse event capture on NSViewRepresentable:** For overlays that MUST capture mouse events (e.g., cover image drag), override `mouseDownCanMoveWindow` → `false`, `hitTest` → return `self`, `acceptsFirstMouse` → `true`, and use `.activeAlways` tracking area (not `.activeInKeyWindow` — non-activating panels are never key). Use `window.nextEvent(matching:)` event loop pattern (see `PanelEdgeResizeView` and `CoverRepositionNSView`).
- **`.task(id:)` for file replacement:** When file content changes but the path stays the same (e.g., replacing a cover image), include `updatedAt` timestamp in the task ID — not just the file path.
- **Bookmark image memory model:** Render bookmark cards from `thumbnailFileURL` (downsampled asset), not `originalImageFileURL`. Full-size originals are for explicit user actions (open/export) only.
- **Sticky section headers:** `LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders])` makes `Section { } header: { }` headers pin at the top during scroll. Used in FolderDetailView for folder header + sub-folder cards. The header needs an opaque background to prevent content showing through when pinned.
- **DetailPopoverPanel:** Secondary floating NSPanel (`App/DetailPopoverPanel.swift`) that shows detail views adjacent to the main CiderPanel. Triggered via `.showDetailPopover` notification with `userInfo["view"]` (AnyView) and optional `userInfo["preferredWidth"]` (CGFloat). Positions to the right of the main panel by default, falls back to left if no screen space. Expand mode: post `.expandCiderPanelForDetailModal` with `userInfo["minimumWidth"]` — AppDelegate saves and widens CiderPanel, then restores via `.restoreCiderPanelAfterDetailModal`. Sidebar collapses automatically during expand mode.
- **CiderPanel WKWebView drag exclusion:** `isInDraggableArea()` in `CiderPanel.swift` checks `if v is WKWebView { return false }` — without this, dragging inside the TipTap editor moves the entire panel instead of interacting with the editor content.
- **Carbon hotkey fallback:** `BookmarksHotkeyDetector` and `NotesHotkeyDetector` fall back to Carbon `RegisterEventHotKey` / `InstallEventHandler` when `CGEventTap` creation fails (e.g., no Accessibility permission). Both detectors now work without full accessibility access — Opt+N and Opt+B hotkeys register via Carbon API in that case.
- **Delete is non-destructive:** `BookmarksStorage.remove()`, `removeAll()`, and `NotesStorage.delete()` all delegate to `TrashStorage` and return `@discardableResult TrashItem`. Callers in ViewModels capture the result and pass it to `CiderUndoManager.shared.record()` to enable undo. Never add a direct file-deletion path — always go through TrashStorage.
- **Undo toast progress bar:** Both capture toast and undo toast use a repeating `Timer` at `BookmarksToastDesign.reviewProgressTickInterval` (1/30s). Model is an `ObservableObject` with `@Published var progress: CGFloat = 1`. Hover pauses the timer; unhover resumes. Match this pattern for any future timed toast.
- **Card container contract:** Every card view (BookmarkCard, NoteCardView, DateCardCardView, ContactCardCardView) MUST use `.cardContainer(isHovered:isSelected:isDropTargeted:)` — never inline a `RoundedRectangle` with manual background/border/clip. Border priority inside `cardContainer`: selected > dropTargeted > hovered > default. `isDropTargeted` defaults to `false` so existing call sites need no changes when adding drop support.
- **BookmarkCard thumbnail drop is self-contained:** `BookmarkCard` calls `BookmarksStorage.shared.assignThumbnail(...)` directly and posts `.showBookmarkCaptureToast` itself. There are NO `onAssignThumbnailFrom*` callback properties — do not add them back. Any view that renders `BookmarkCard` gets drag-and-drop thumbnail assignment for free with no wiring.
- **`nonisolated static` for View helpers called off main thread:** Pure utility static methods on SwiftUI `View` structs that are called from `NSItemProvider` callbacks (non-isolated background threads) must be marked `nonisolated static`. Without it, the compiler emits a main-actor isolation warning. Example: `BookmarkCard.preferredImageFileExtension(for:)`.
- **Popovers anchored to SwiftUI views — always use `.popover()`, never manual NSPopover:** SwiftUI's `.popover(isPresented:, arrowEdge:)` positions correctly for views inside `NSHostingView` in non-activating panels. Manual `NSPopover.show(relativeTo:of:)` with a `PopoverAnchorView` NSView is unreliable — the NSView's reported frame in the AppKit hierarchy is misaligned with the visual position due to coordinate system inconsistencies between the flipped `NSHostingView` and its non-flipped NSView children. `PopoverAnchorView.swift` is kept only for possible future use but should not be used for popover anchoring.
- **ViewBridge/RemoteViewService crash in `.popover()` content (non-activating panel):** SwiftUI popovers render content in a remote XPC process (RemoteViewService). Two things crash it: (1) `@FocusState` + async `.task { focused = true }` inside popover forms — async focus events fire into a partially-ready XPC context; (2) `withAnimation` / `.animation()` on content that changes height — animated popover resizes over XPC fail and call back through a nil function pointer (crash at `0x00000000`, "Unable to obtain a task name port right" in logs). Fix: no `@FocusState` in popover forms, no animation on content changes. Simple SwiftUI popovers with static content (e.g. `ViewOptionsDropdown`) are fine. Also: never use `DatePicker(.field)` or `DatePicker(.compact)` inside a popover in a non-activating panel — both open popup calendars that crash the same way. Use plain `TextField` with date string parsing instead.
- **+New popover (`NewItemPopover.swift`):** 3×2 grid of type cards: Bookmark, Note, Event, Contact, Folder, Tab. No `@FocusState` or animations anywhere in the popover. Event form uses plain text fields for date ("Feb 21, 2026") and time ("2:30 PM") with `DateFormatter` multi-format parsing. Tab form creates a `SavedView` (isTabPinned: true) with selected entity type filter; panel navigates immediately to the new tab.
