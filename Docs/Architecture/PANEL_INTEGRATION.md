# Panel Integration Reference

> Combines panel architecture (structure, layout, display modes, search, settings, sync) with SwiftUI + NSPanel gotchas. Read this when working on panel layout, display mode logic, search, settings, or debugging layout/focus/popover/drag-drop/keyboard issues.
>
> *Consolidates the former ARCHITECTURE.md and SWIFTUI_GOTCHAS.md.*

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
│   │   │   ├── Tags section (filter chips / collapsible)
│   │   │   └── Pinned sources section (when linked sources are enabled)
│   │   └── sidebarFooter (gear + "New" pill menu + view options)
│   └── VStack (right column, top padding aligns title bar center with traffic lights)
│       ├── titleBar (animated sidebar toggle + CiderTabBar + capture button)
│       ├── Divider (14pt horizontal inset, aligned with card content edges)
│       └── contentArea (switches by selectedTab)
│           ├── TagDetailView (when tag filters are active or Tag tab is selected)
│           ├── SourceDetailView (when a linked source is selected)
│           ├── FolderDetailView (when folder selected — overrides tab content)
│           ├── Saved view tabs
│           │   ├── HomeDashboardView (standard saved/library views)
│           │   ├── WhiteboardTabView
│           │   ├── OnboardingTabView
│           │   └── Blank-tab welcome state
│           ├── SearchTabContent (spawned searches)
│           ├── Tag manager tab
│           ├── AIChatView (when docked as a tab)
│           └── Empty state (when no tabs exist)
├── compactOverlaySidebar (< 680pt, slides over content)
├── SearchPaletteView (overlay)
├── Detail overlays
│   ├── bookmark detail (full-panel / slide-out / page)
│   ├── generic card detail (date/contact/todo/file/session)
│   └── note detail/editor (full-panel / slide-out / page)
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
- Grid/Masonry: BookmarkCard + NoteCardView + DateCardCardView + ContactCardCardView + TodoCardCardView
- List: Unified LibraryTableView — all item types share the same table row layout
- Continue section: sticky 8-item recents, two-column, collapsible
- Library feed: scrollable mixed feed, filters by folder selection

### Unified Table List View (list mode)
When displayMode == .list, HomeDashboardView/FolderDetailView/SavedViewTabContent
use the shared table component instead of per-type list rows:

- LibraryTableView — self-contained table with sticky header + scrollable rows
- LibraryTableRows — embeddable rows for views with existing ScrollViews
- LibraryTableHeader — column headers with draggable resize handles + column picker
- LibraryTableRow — single row rendering any LibraryItemV2 uniformly

9 columns: Name (flexible), Type, Tags, Folder, Created, Modified, URL, Words, Priority
- Name column fills remaining space; other columns have fixed widths
- Column widths, order, and visibility persisted in CiderConfig.tableColumnConfig
- TableColumnConfig stored as JSON in UserDefaults (backward-compatible)
- Default visible: Name, Type, Tags, Created, Modified
- Hidden by default: Folder, URL, Words, Priority (toggled via + button)

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

**Scope modifiers** (`SearchScope` + `SearchService.parseScope`): Queries can contain `@`-prefixed scope modifiers that filter results before token matching:
- Entity type: `@bookmarks`, `@notes`, `@events`, `@contacts` (prefix matching: `@b` works). Multiple combine (OR).
- Folder: `@folder:Name` (multi-word, prefix match, case-insensitive). `@folder:` (bare) = all folder-assigned items. Multiple `@folder:` scopes combine (OR). Results grouped by folder with headers in Cmd+K.
- Tag: `@tag:Name` (prefix match, case-insensitive).
- Shorthand: `@f:` for folder, `@t:` for tag.
- `SearchScope` struct holds parsed scopes + `cleanQuery` (remaining text after scope extraction).
- Scope pills (blue badges) shown below search field in Cmd+K when active.
- Works in Cmd+K palette, search tabs, sidebar search, and saved view filtering (`LibraryViewModel.filteredItems` parses scopes from `textQuery`).
- Sidebar search on Inbox tab: `onlyUnassigned` is overridden when a `@folder:` scope is active.

**SpotlightIndexer** (`Services/SpotlightIndexer.swift`) indexes all items into Core Spotlight for system-wide search (Spotlight, Raycast, Alfred). Subscribes to storage `$published` properties with 2-second debounce. Gated by `CiderConfig.enableSpotlightIndexing`. Note: Core Spotlight requires a proper `.app` bundle — SPM executables silently fail to surface items. Indexing code is ready but dormant during development builds.

---

## Settings Architecture

Settings categories live in `SettingsCategory` enum. Adding a new top-level settings section requires: (1) new case in `SettingsCategory`, (2) add to `primaryCategories`, (3) new case(s) in `SettingsSubcategory`, (4) wire in `subcategories` switch and `selectedSubcategoryContent` switch. Current categories: General, Notes, Bookmarks, Appearance, Data, Advanced, About. Data subcategories: Directories (vault root + per-type override pickers), Trash (`StorageSettingsView`), Notifications (toast position pickers), Cider Web Sync (`SyncSettingsView`). Notes subcategories: Behavior, Editor. Bookmarks subcategory: Behavior (no directory picker — moved to Data → Directories). Deep-link string for "View Trash" undo toast is `"data"` (navigates to `.data` category). The sync token field is persisted through `SyncService.saveSyncToken()` into Keychain; `CiderConfig.syncToken` remains as a legacy migration path, not the primary storage location.

## Cider Web Sync

Cider Web is a companion web app that lets users capture bookmarks from their phone and sync them to the desktop app. Sync is entirely optional — disabled by default.

**Architecture:**
- `SyncService` (`Services/SyncService.swift`) — `@MainActor` singleton using `ConvexClient`
- Authenticates once via `sync:authenticate`, then subscribes to `sync:changeSignal` over the Convex client
- Pushes local changes with `sync:push`; pulls remote changes with `sync:pull`
- Reactive by default: remote edits trigger a debounced pull when the change signal advances
- Local notes still use a 30-second dirty-note timer because editor/file-save side effects make fully event-driven push unsafe
- Conflict resolution: last-write-wins based on `updatedAt` timestamps
- Deletion tracking: bookmark, folder, and note deletions are queued in UserDefaults and pushed on the next sync pass
- Authentication: user enters a Convex site URL plus sync token in Settings → Data → Cider Web Sync; token is stored in Keychain
- Transport guardrails: desktop sync refuses to start unless the configured site URL is HTTPS and can be converted into a Convex deployment URL

**Sync flow:**
1. **Startup/auth** — `SyncService.startIfEnabled()` migrates any legacy token to Keychain, validates config, creates one `ConvexClient`, authenticates with `sync:authenticate`, and installs the reactive change subscription
2. **Push** — local bookmarks, folders, notes, and pending deletion tombstones are serialized into Convex action arguments and sent with `sync:push`
3. **Pull** — `sync:pull` is called with the last known server timestamp to fetch new/updated/deleted bookmarks, folders, and notes
4. **Apply** — pull handlers create or update local models from sync IDs, remove server-deleted models, and advance `lastSyncTimestamp`
5. **Steady state** — remote edits trigger debounced pulls; local edits call `pushAfterLocalChange()`; notes also get a periodic dirty check every 30 seconds
6. Server timestamp saved to `CiderConfig.lastSyncTimestamp` for incremental pulls

**CiderConfig properties:** `syncEnabled`, `syncURL`, `lastSyncTimestamp`

**Storage sync methods:**
- `addFromSync(id:title:urlString:...)` — creates bookmark with specific UUID, triggers enrichment
- `updateFromSync(bookmarkID:title:...)` — updates fields, sets `updatedAt` to now
- `removeSynced(_:)` — removes without trashing (no undo toast)
- Folders and notes have equivalent sync-specific create/update/remove paths keyed by sync IDs

**Settings UI:** `SyncSettingsView` under Data → Cider Web Sync. Fields: Convex site URL, sync token (SecureField), enable toggle, status indicator (syncing/error/last synced), Sync Now button.

**Backend:** Convex (convex.dev). The desktop app derives a deployment URL from the configured `.convex.site` URL, then uses the Convex Swift SDK for actions and subscriptions rather than direct REST polling.

**Important:** Sync currently covers bookmarks, folders, and notes. Date cards, contacts, todos, vault files, sessions, and tags remain local-only.

---

# SwiftUI + NSPanel Gotchas

> Hard-won lessons from building SwiftUI views inside non-activating NSPanels. Reference these when debugging layout, focus, popover, drag-and-drop, or keyboard issues in the panel.

---

## Layout & Clipping

- **Animated content clipping:** Content with slide transitions (`.move(edge:)`) must have `.clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))` — otherwise animations overflow into the shadow area drawn by `AcrylicPanelBackground`. The shadow sits underneath in the ZStack and is unaffected by clipping the content layers above it.
- **VisualEffectView in overlays:** Use `.withinWindow` blending (not `.behindWindow`) for views overlaying the panel's own content. Our window background is `.clear` for custom shadows, so `.behindWindow` samples the desktop wallpaper. Only `AcrylicPanelBackground` should use `.behindWindow`.
- **ScrollView bottom padding:** Padding on content INSIDE a ScrollView doesn't prevent clipping at the panel edge — the scroll area itself still extends to the edge. Put bottom padding OUTSIDE the ScrollView (on the ScrollView itself) so the scroll area is inset from the panel.
- **Compact mode GeometryReader:** Measure panel width (HStack), NOT content area width. Content width changes when sidebar toggles, causing infinite collapse/expand feedback loop. Panel width is stable.
- **Prefer inline GeometryReader over PreferenceKey:** `onPreferenceChange` fires with the `defaultValue` (often `0`) before the real measurement arrives, causing incorrect initial state. Inline `GeometryReader { proxy in let x = proxy.size.width ... }` is simpler and avoids this race.
- **GeometryReader threshold anti-oscillation:** When a threshold controls layout (e.g., 1 vs 2 columns), set it high enough that sidebar show/hide (~200pt delta) can't flip the result. Otherwise content width jumps when sidebar toggles, causing column flicker.
- **MasonryLayout cache:** `computeFrames` has no width-only cache across layout passes — subview sizes can change independently (e.g., `BookmarkCard.@State cardWidth` updating via GeometryReader). However, `placeSubviews` skips recomputation when width matches `sizeThatFits` (safe within same layout pass). `sizeThatFits` always recomputes to catch subview size changes.
- **Sticky section headers:** `LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders])` makes `Section { } header: { }` headers pin at the top during scroll. Used in FolderDetailView for folder header + sub-folder cards. The header needs an opaque background to prevent content showing through when pinned.

## Context Menus

- **Never use SwiftUI `.contextMenu`** in lazy containers — it caches content and goes stale after data changes. Use the shared `CardContextMenu` (`Utilities/CardContextMenu.swift`) which builds a fresh native `NSMenu` on every right-click.
- **NSView overlays:** When overlaying `NSViewRepresentable`, override `hitTest` to return `nil` for non-target events — otherwise the overlay blocks left clicks, hovers, and drags from reaching SwiftUI content underneath.

## Focus & Keyboard

- **@FocusState in NSPanel:** Non-activating panels need a delay before focus takes effect — use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }`
- **Escape key in NSPanel:** `.onExitCommand` does NOT work with `.nonactivatingPanel` — use a hidden `Button("") { ... }.keyboardShortcut(.escape, modifiers: [])` in `.background {}` instead.
- **Modifier detection in Button actions:** Use `NSEvent.modifierFlags` (static property) to check `.command` / `.shift` at click time. Works inside Button action closures without needing gesture composition.

## Popovers

- **Always use SwiftUI `.popover()`, never manual NSPopover:** SwiftUI's `.popover(isPresented:, arrowEdge:)` positions correctly for views inside `NSHostingView` in non-activating panels. Manual `NSPopover.show(relativeTo:of:)` with a `PopoverAnchorView` NSView is unreliable — the NSView's reported frame in the AppKit hierarchy is misaligned with the visual position due to coordinate system inconsistencies between the flipped `NSHostingView` and its non-flipped NSView children. `PopoverAnchorView.swift` is kept only for possible future use but should not be used for popover anchoring.
- **ViewBridge/RemoteViewService crash in `.popover()` content (non-activating panel):** SwiftUI popovers render content in a remote XPC process (RemoteViewService). Two things crash it: (1) `@FocusState` + async `.task { focused = true }` inside popover forms — async focus events fire into a partially-ready XPC context; (2) `withAnimation` / `.animation()` on content that changes height — animated popover resizes over XPC fail and call back through a nil function pointer (crash at `0x00000000`, "Unable to obtain a task name port right" in logs). Fix: no `@FocusState` in popover forms, no animation on content changes. Simple SwiftUI popovers with static content (e.g. `ViewOptionsDropdown`) are fine. Also: never use `DatePicker(.field)` or `DatePicker(.compact)` inside a popover in a non-activating panel — both open popup calendars that crash the same way. Use plain `TextField` with date string parsing instead.
- **+New popover (`NewItemPopover.swift`):** 3x2 grid of type cards: Bookmark, Note, Event, Contact, Folder, Tab. No `@FocusState` or animations anywhere in the popover. Event form uses plain text fields for date ("Feb 21, 2026") and time ("2:30 PM") with `DateFormatter` multi-format parsing. Tab form creates a `SavedView` (isTabPinned: true) with selected entity type filter; panel navigates immediately to the new tab.

## Drag & Drop

- **Custom UTIs in `.onDrop`:** `hasItemConformingToTypeIdentifier()` and `registeredTypeIdentifiers.contains()` both fail for unregistered custom UTIs (e.g., `com.cider.multi-drag`). Encode payloads in `public.utf8-plain-text` with a distinctive prefix (e.g., `cider-multi-drag:JSON`) and detect via text parsing in drop handlers.
- **Drag preview clipping:** `scaleEffect`, `rotationEffect`, and `offset` on `.onDrag(preview:)` views push content outside the view's natural bounds. macOS clips the preview window to those bounds. Add explicit `.padding()` before transforms to prevent clipping.
- **Multi-drag provider types:** Don't register single-item type identifiers on multi-drag providers — the single-item drop handler fires first (by order in `handleFolderDrop`) and intercepts the drop, ignoring the multi-drag payload.
- **onDrop concurrency:** `loadDataRepresentation` callbacks are non-isolated. Capture view model references locally before the closure, then do lookups inside `Task { @MainActor in }` to avoid main-actor-isolation warnings.

## Mouse Events & NSViewRepresentable

- **Mouse event capture on NSViewRepresentable:** For overlays that MUST capture mouse events (e.g., cover image drag), override `mouseDownCanMoveWindow` → `false`, `hitTest` → return `self`, `acceptsFirstMouse` → `true`, and use `.activeAlways` tracking area (not `.activeInKeyWindow` — non-activating panels are never key). Use `window.nextEvent(matching:)` event loop pattern (see `PanelEdgeResizeView` and `CoverRepositionNSView`).

## View Lifecycle & Data

- **Card data refresh:** Use `.task(id: note.modifiedAt)` not `.task(id: note.id)` so card data reloads after edits.
- **`.task(id:)` for file replacement:** When file content changes but the path stays the same (e.g., replacing a cover image), include `updatedAt` timestamp in the task ID — not just the file path.
- **Home tab kept alive:** `HomeDashboardView` is always in the view tree (ZStack with `opacity(isHomeActive ? 1 : 0)` + `allowsHitTesting`). Switching tabs doesn't destroy it — thumbnails, card data, and scroll position persist. Other tabs (saved views, search, external sources) still create/destroy on demand. `isHomeActive = selectedTab == .home && selectedFolderID == nil && selectedSourceID == nil`.
- **Folder view condition order:** In `tabContentBody`, check `selectedFolderID != nil` BEFORE the ZStack that contains Home — otherwise Home renders instead of FolderDetailView when a folder is selected on the Home tab.
- **Tab deselection in folder view:** CiderTabBar takes `selectedFolderID` binding. `isSelected = selectedTab == tab && selectedFolderID == nil`. Clicking a tab sets `selectedFolderID = nil` so re-clicking the same tab works to exit folder view.
- **Inline note editor:** Notes open inline within CiderPanelView via push/pop navigation (`editingNoteID` state). Editor takes over the content area; title bar swaps to back button + editable title + formatting controls. Escape or back button closes the editor, flushes save, and returns to the previous view.
- **Text concatenation:** `Text("a") + Text("b")` is deprecated in macOS 26. Use `Text(AttributedString)` with per-range attributes instead.

## Card & Container Contracts

- **Card container contract:** Every card view (BookmarkCard, NoteCardView, DateCardCardView, ContactCardCardView) MUST use `.cardContainer(isHovered:isSelected:isDropTargeted:)` — never inline a `RoundedRectangle` with manual background/border/clip. Border priority inside `cardContainer`: selected > dropTargeted > hovered > default. `isDropTargeted` defaults to `false` so existing call sites need no changes when adding drop support.
- **BookmarkCard thumbnail drop is self-contained:** `BookmarkCard` calls `BookmarksStorage.shared.assignThumbnail(...)` directly and posts `.showBookmarkCaptureToast` itself. There are NO `onAssignThumbnailFrom*` callback properties — do not add them back. Any view that renders `BookmarkCard` gets drag-and-drop thumbnail assignment for free with no wiring.
- **Bookmark image memory model:** Render bookmark cards from `thumbnailFileURL` (downsampled asset), not `originalImageFileURL`. Full-size originals are for explicit user actions (open/export) only.
- **Shared view parameter changes:** `BookmarksBrowserView` is used by `CiderPanelView` (and potentially multiple call sites within it). When adding required parameters, update ALL call sites.

## AppKit Integration Gotchas

- **NSOpenPanel from non-activating panel:** Call `NSApp.activate(ignoringOtherApps: true)` before `runModal()` — otherwise the file picker sidebar isn't fully interactive (requires multiple clicks). Don't set `panel.level = .floating` on the open panel.
- **Shadow shapes use literal `Color.black`** — this is correct, not a CiderColors violation. The custom shadow pattern (blurred black RoundedRectangle) is intentional.
- **AppKit Reduce Motion:** For `NSAnimationContext` code (panel collapse), check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — `@Environment(\.accessibilityReduceMotion)` is SwiftUI-only.
- **SourceKit false positives:** "Cannot find 'CiderFont' in scope" (and similar cross-file type errors) are SourceKit indexing noise, not real build errors. Ignore them — verify with `swift build` instead.
- **System sounds:** `NSSound` fails silently in `.accessory` activation apps (`AddInstanceForFactory` error). Use `AudioServicesPlaySystemSound` (AudioToolbox) instead. See `CiderSoundEffect.swift`.
- **`nonisolated static` for View helpers called off main thread:** Pure utility static methods on SwiftUI `View` structs that are called from `NSItemProvider` callbacks (non-isolated background threads) must be marked `nonisolated static`. Without it, the compiler emits a main-actor isolation warning. Example: `BookmarkCard.preferredImageFileExtension(for:)`.
- **DetailPopoverPanel:** Secondary floating NSPanel (`App/DetailPopoverPanel.swift`) that shows detail views adjacent to the main CiderPanel. Triggered via `.showDetailPopover` notification with `userInfo["view"]` (AnyView) and optional `userInfo["preferredWidth"]` (CGFloat). Positions to the right of the main panel by default, falls back to left if no screen space. Expand mode: post `.expandCiderPanelForDetailModal` with `userInfo["minimumWidth"]` — AppDelegate saves and widens CiderPanel, then restores via `.restoreCiderPanelAfterDetailModal`. Sidebar collapses automatically during expand mode.

## Caching & Performance

- **CiderFont scale is cached:** `CiderFont._cachedScale` (`nonisolated(unsafe) static var`) is set at startup and refreshed by `CiderFont.invalidateScale()` at the top of `handleConfigChanged()`. Font tokens read the cached value — no UserDefaults decode per render. If you add a new config-driven font property, call `invalidateScale()` from `handleConfigChanged()`. Only `heroDisplay(scale:)` takes an explicit parameter; all other tokens respond automatically.
- **StoragePaths vault caching:** `StoragePaths` caches per-type directory URLs in `_cachedTypeURLs` and the vault root in `_cachedVaultURL` (both `nonisolated(unsafe) static var`). Use `cachedDirectoryURL(for:)` in render paths and view closures. Invalidated by `StoragePaths.invalidateCachedDirectory()` in `handleConfigChanged()`. `Bookmark.thumbnailFileURL`/`originalImageFileURL` and `Note.resolvedContent`/`imageURLs` use these cached paths. Never call `CiderConfig.load()` in view body or computed properties that run during render — use cached paths or `@State config` instead.
- **Undo toast progress bar:** Both capture toast and undo toast use a repeating `Timer` at `BookmarksToastDesign.reviewProgressTickInterval` (1/30s). Model is an `ObservableObject` with `@Published var progress: CGFloat = 1`. Hover pauses the timer; unhover resumes. Match this pattern for any future timed toast.

## Build & Project

- **Xcode + SPM hybrid project:** `Cider.xcodeproj` wraps the SPM package for code signing. Only open one at a time — having both `Package.swift` and `.xcodeproj` open in Xcode simultaneously causes "Couldn't load package" / "Missing package product" errors.
- **SWIFT_MODULE_NAME on app target:** The Xcode app target sets `SWIFT_MODULE_NAME = CiderApp` to avoid a Swift module name collision with the SPM library (both would default to "Cider" from `PRODUCT_NAME = Cider`). Do not remove this setting.
- **Bundle.module vs Bundle.main:** Resources excluded from SPM via `exclude:` in `Package.swift` (TipTapEditor, ReaderMode) are owned by the Xcode target. Those call sites use `Bundle.main`, not `Bundle.module`. If adding new SPM-excluded resources, update the call site too.
- **Nested types in dead files:** Before deleting a "dead" file, grep for ALL types it defines (not just the primary struct). BookmarksBrowserView.swift contained `BookmarkThumbnailView` and `BookmarkVisualStyle` used elsewhere.

## Storage & Data Integrity

- **Delete is non-destructive:** `BookmarksStorage.remove()`, `removeAll()`, `NotesStorage.delete()`, `DateCardStorage.deleteDateCard()`, and `ContactStorage.deleteContact()` all delegate to `TrashStorage` and return `@discardableResult TrashItem` (or `TrashItem?`). Callers capture the result and pass it to `CiderUndoManager.shared.record()` to enable undo. Never add a direct file-deletion path — always go through TrashStorage. For bulk deletes across entity types, call storage methods directly (not ViewModel wrappers) and collect all trash items into a single `bulkDeletedToTrash` recording — `CiderUndoManager` only tracks one pending action.
- **Image bookmarks have empty `urlString`:** `addImageBookmark(title:)` creates with `urlString: ""`. Both `loadFromDisk` and `buildSnapshotFromFiles` must append empty-URL bookmarks from metadata JSON after the HTML merge loop — `NetscapeBookmarksCodec.decode` skips empty hrefs.
- **Clipboard monitor suspension:** `ActiveBrowserCaptureService.captureViaShortcut()` restores the pasteboard after reading browser URL, incrementing `changeCount`. When `BookmarksClipboardMonitor` suspension expires, it must reset `lastChangeCount` to current value to avoid re-detecting stale clipboard changes. Image data may also be lazily provided by source apps — the monitor schedules a 400ms retry via `DispatchWorkItem`.
- **BookmarksStorage class boundary:** The `BookmarksStorage` class closes around line 1600. Everything after is file-private types (`BookmarkEnrichmentPayload`, `EnrichmentRetryThresholds`, `BookmarkMetadataParser`, `NetscapeBookmarksCodec`). When adding instance methods, insert them BEFORE the class `}` — not at the end of the file — or they'll silently land inside a private enum and `bookmarks`/`persist` won't be in scope.
- **ActiveBrowserCaptureService browser candidate filter:** `target(from:)` requires `activationPolicy == .regular` AND `bundleURL` exists on disk before creating a `BrowserTarget`. This blocks ghost Dock Extras (uninstalled apps still registered) and XPC/helper processes (`.accessory`/`.prohibited` policy) from reaching the AppleScript layer, where they would trigger macOS "Where is <App>?" system pickers. Preserve both guards when modifying this function.

## NSView / AppKit Deep

- **CiderPanel WKWebView drag exclusion:** `isInDraggableArea()` in `CiderPanel.swift` checks `if v is WKWebView { return false }` — without this, dragging inside the TipTap editor moves the entire panel instead of interacting with the editor content.
- **Carbon hotkey fallback:** `BookmarksHotkeyDetector` and `NotesHotkeyDetector` fall back to Carbon `RegisterEventHotKey` / `InstallEventHandler` when `CGEventTap` creation fails (e.g., no Accessibility permission). Both detectors now work without full accessibility access — Opt+N and Opt+B hotkeys register via Carbon API in that case.
- **Layer-backed NSView transparency:** `.clear` CGContext blend mode does NOT punch through to show content below in `wantsLayer = true` views — it clears the layer to transparent but the composited result depends on window blending, not the pixels below. To create a "hole" in a dim overlay (e.g. screen capture selection), draw the dim as 4 rects around the selection instead of fill-all + clear-hole.
