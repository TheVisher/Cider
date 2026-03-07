# Cider Architecture Reference

> Internal architecture details: panel structure, layout alignment rules, display modes, search, and settings. Read this when working on panel layout, display mode logic, search, or settings.

---

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

---

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

---

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

---

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

---

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

---

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

---

## Settings Architecture

Settings categories live in `SettingsCategory` enum. Adding a new top-level settings section requires: (1) new case in `SettingsCategory`, (2) add to `primaryCategories`, (3) new case(s) in `SettingsSubcategory`, (4) wire in `subcategories` switch and `selectedSubcategoryContent` switch. Current categories: General, Notes, Bookmarks, Appearance, Data, Advanced, About. Data subcategories: Directories (vault root + per-type override pickers), Trash (`StorageSettingsView`), Notifications (toast position pickers). Notes subcategories: Behavior, Editor. Bookmarks subcategory: Behavior (no directory picker — moved to Data → Directories). Deep-link string for "View Trash" undo toast is `"data"` (navigates to `.data` category).
