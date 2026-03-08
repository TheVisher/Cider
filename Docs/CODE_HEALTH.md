# Cider Code Health

> **Living document.** Do not replace or rewrite — update it in place.
> Items are checked off when fixed, never deleted. New findings are appended under the appropriate section.

---

## Agent Instructions

**Before starting a code review:**

- Read this file first. Do not re-report findings that are already listed here (open or resolved).
- Identify the highest-severity open items and call them out in your review.

**When you fix something on this list:**

- Check the item's checkbox and add the date: `✅ Fixed YYYY-MM-DD`

**When a code review surfaces a new finding:**

- Add it under the correct section using the next available ID (e.g., `CH-C05`).
- Include severity, a short description, and file refs.
- Leave it unchecked.

**Severity guide:** `Critical` → `High` → `Medium` → `Low`

---

## Security

### ~~CH-S01 — WKWebView root filesystem access~~ ✅ Fixed 2026-02-21

Changed `allowingReadAccessTo: URL(fileURLWithPath: "/")` to `URL(fileURLWithPath: NSHomeDirectory())` in `NotesViewModel.swift`. WebView can now only read from the user's home directory, not the entire filesystem.

### ~~CH-S02 — WebView bridge exposure via HTML + navigation policy~~ ✅ Fixed 2026-02-21

Navigation policy in `TipTapEditorCoordinator` changed to deny-by-default. Only `file://` (editor HTML + local images) and `about:` (initial blank) are allowed through. All other schemes are blocked regardless of `navigationType` — the previous code only blocked `.linkActivated`, leaving JS-triggered navigations open. User-clicked external links still open in the system browser before being cancelled.

### ~~CH-S03 — SSRF / Local network scanning via Bookmark Enrichment~~ ✅ Fixed 2026-02-28

Added URL scheme validation in `fetchHTMLEnrichmentPayload` — only `http` and `https` schemes are allowed. All other schemes (file, ftp, etc.) return `nil` before any network request is made.

- File refs: `Sources/Cider/Services/BookmarksStorage.swift`

### ~~CH-S04 — Symlink traversal in ExternalSourceScanner~~ ✅ Fixed 2026-02-28

Added `.isSymbolicLinkKey` to resource keys in `scan()` and filter that rejects symbolic links. Only regular `.md` files are included in scan results.

- File refs: `Sources/Cider/Services/ExternalSourceScanner.swift`

### CH-S05 — Sync token stored in plaintext config and sent without HTTPS enforcement

**Severity:** High

`syncToken` is still stored inside `CiderConfig` and persisted directly to `UserDefaults`. `SyncService.syncRequest` also accepts any configured URL and always attaches `Authorization: Bearer ...` without enforcing `https://`.

- File refs: `Sources/Cider/Models/CiderConfig.swift`, `Sources/Cider/Views/Settings/SyncSettingsView.swift`, `Sources/Cider/Services/SyncService.swift`

### CH-S06 — Bookmark enrichment leaks full page URL via `Referer` and public logs

**Severity:** Medium

Remote thumbnail downloads still forward `pageURL.absoluteString` as the `Referer`, which can leak sensitive query params/tokens to third-party image hosts. Enrichment and WebView extraction also log titles, hosts, and image URLs with `privacy: .public`.

- File refs: `Sources/Cider/Services/BookmarksStorage.swift`, `Sources/Cider/Services/WebViewMetadataExtractor.swift`

### CH-S07 — Clipboard URL favicon fetch leaks copied domains to third parties

**Severity:** Medium

Saving a URL clipboard item automatically triggers favicon requests to DuckDuckGo and Google, leaking copied domains without an explicit user action.

- File refs: `Sources/Cider/Services/ClipboardStorage.swift`

---

## Correctness / Data

### ~~CH-C01 — Storage path split on directory change~~ ✅ Fixed 2026-02-21

`fileURL` in ContactStorage, ProjectStorage, DateCardStorage, CardStackStorage, CardLabelStorage, SavedViewStorage, and ExternalSourceStorage changed from stored properties (set at `init()`) to computed properties that call `StoragePaths.ciderDataDirectoryURL()` at runtime. Each storage gained a public `reload()` method. `AppDelegate.handleConfigChanged()` calls `reload()` on all 6 after updating the BookmarksStorage directory. Also: `CiderConfig.bookmarksDirectory` renamed to `ciderDataDirectory`; CodingKeys alias keeps JSON key `"bookmarksDirectory"` for backward compat.

### ~~CH-C02 — Note restore orphan risk in TrashStorage~~ ✅ Fixed 2026-02-21

Move is now `try fm.moveItem` inside a `do/catch`; on failure, function returns early leaving the manifest intact. `restoreFromTrash` and `removeFromManifest` only called on success. If the trash file is already gone (manual deletion), manifest is cleaned but index is not updated.

### ~~CH-C03 — Note search false negatives from 120-char cap~~ ✅ Fixed 2026-02-21

`notePreview` renamed `noteStrippedContent` and returns the full stripped string. `searchNotes` matches against the full content; `prefix(120)` applied only to the `subtitle` field in the returned `SearchResult`.

### ~~CH-C04 — Select All skips date cards and contacts on Home tab~~ ✅ Fixed 2026-02-25 (F-07)

`selectAll()` in `CiderPanelView` updated to include date cards and contacts. Bulk-delete/move now supports all entity types.

- File refs: `Sources/Cider/Views/CiderPanelView.swift`

### ~~CH-C05 — Orphan attachment cleanup race condition~~ ✅ Fixed 2026-02-28

Added `creationDate` check alongside `modificationDate` in orphan cleanup. Uses `max(modifiedAt, createdAt)` so recently created files are never prematurely deleted, even if their modification date hasn't been updated yet.

- File refs: `Sources/Cider/Services/NotesStorage.swift`

### ~~CH-C06 — Short UUID collision risk in attachments~~ ✅ Fixed 2026-02-28

Changed `UUID().uuidString.prefix(8)` to `UUID().uuidString` for attachment filenames. Also increased note title uniqueness suffix from `prefix(4)` to `prefix(8)`.

- File refs: `Sources/Cider/Services/NotesStorage.swift`

### ~~CH-C07 — Complex logic lacks unit tests~~ ✅ Fixed 2026-02-28

`NotesMarkdownPathCodec`: 4 tests in `NotesMarkdownPathCodecTests.swift` (fixed 2026-02-24). `NetscapeBookmarksCodec`: 10 tests in `NetscapeBookmarksCodecTests.swift` covering decode (standard, empty href, HTML entities, missing title, empty/non-bookmark input), encode (standard, special characters), and round-trip (URL/title/date preservation). Codec changed from `private` to `internal` for testability.

- File refs: `Tests/CiderTests/NetscapeBookmarksCodecTests.swift`, `Tests/CiderTests/NotesMarkdownPathCodecTests.swift`

### ~~CH-C08 — Search results for Date Cards/Contacts are non-functional~~ ✅ Fixed 2026-02-24 (F-06)

Search result selection for date cards and contacts now opens detail/edit flows in both SearchPaletteView and SearchTabContent.

- File refs: `Sources/Cider/Views/Search/SearchPaletteView.swift`, `Sources/Cider/Views/Search/SearchTabContent.swift`

### ~~CH-C09 — `enablePageSummaries` setting is not enforced in Reader summary trigger~~ ✅ Fixed 2026-02-24

Added `CiderConfig.load().enablePageSummaries` guard to the summary generation condition in `BookmarkReaderView.showReader()`. Summaries now only trigger when the setting is enabled.

- File refs: `Sources/Cider/Views/Bookmarks/BookmarkReaderView.swift`

### ~~CH-C10 — +New Tab can create saved views while saved-view tabs are feature-flag hidden~~ ✅ Fixed 2026-02-24

`NewItemPopover` now takes `enableSavedViewTabs` parameter and conditionally shows the Tab card. `onCreateTab` closure in `CiderPanelView` now auto-enables the flag (matching `createSavedViewFromCurrentHomeState` pattern) before selecting the new tab.

- File refs: `Sources/Cider/Views/CiderPanelView.swift`, `Sources/Cider/Views/Shared/NewItemPopover.swift`

### ~~CH-C11 — `NotesStorage.updateDirectory` async transition breaks synchronous expectations~~ ✅ Fixed 2026-02-28

`updateDirectory(to:)` now clears `notes` and `index` synchronously before starting the async scan. This prevents stale data from being accessed during the transition and makes the transient empty state explicit rather than a race condition.

- File refs: `Sources/Cider/Services/NotesStorage.swift`

### ~~CH-C12 — Bookmark labels are not represented in unified library filtering~~ ✅ Already correct (verified 2026-02-28)

`LibraryItemV2.labelIDs` correctly returns `Set(bookmark.labelIDs)` and `Set(note.labelIDs)` — the original report was inaccurate. Label-based filtering works for all entity types that have labels.

- File refs: `Sources/Cider/Models/LibraryItemV2.swift`

### ~~CH-C13 — SavedViewTabContent.itemCard() deletes without TrashStorage or undo~~ ✅ Fixed 2026-02-24

`itemCard()` called `DateCardStorage.deleteDateCard` / `ContactStorage.deleteContact` directly, bypassing `TrashStorage` and `CiderUndoManager`. Grid/masonry deletes were permanent with no undo. Fixed to match `itemRow()` pattern: route through `TrashStorage.shared.trashDateCard` / `trashContact` and record undo action.

- File refs: `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift`

### ~~CH-C14 — Force unwrap crash in HighlightedText on Unicode text~~ ✅ Fixed 2026-02-24

`AttributedString.Index(_:within:)!` force unwraps could crash when `lowercased()` changes string length (e.g., "ß" → "ss"). Replaced with `guard let` safe unwrap that skips the match on conversion failure.

- File refs: `Sources/Cider/Utilities/HighlightedText.swift`

### CH-C15 — `NotesStorage.updateDirectory` still breaks synchronous callers and regression test

**Severity:** High

Although `updateDirectory(to:)` now clears stale state synchronously, it still repopulates `notes` and `index` via an unawaited async task. Callers can still observe an empty note list immediately after switching directories, and the regression test `Scan notes tolerates duplicate filename index entries` still fails because `storage.notes.count` is `0` right after `updateDirectory`.

- File refs: `Sources/Cider/Services/NotesStorage.swift`, `Tests/CiderTests/NotesStorageRegressionTests.swift`

### CH-C16 — Dirty-only sync can miss bookmark folder moves

**Severity:** High

`SyncService.push` now only pushes items whose `updatedAt` is newer than `lastSuccessfulPushAt`, but `BookmarksStorage.assignBookmark(_:toFolder:)` still does not bump `updatedAt`. Folder assignment changes can therefore be excluded from sync indefinitely.

- File refs: `Sources/Cider/Services/SyncService.swift`, `Sources/Cider/Services/BookmarksStorage.swift`

### CH-C17 — Sync stop/reconfigure does not cancel in-flight work

**Severity:** Medium

`SyncService.stop()` invalidates the timer but does not cancel the active async sync task. A sync cycle can continue mutating local state after sync is disabled or reconfigured.

- File refs: `Sources/Cider/Services/SyncService.swift`

### CH-C18 — Folder parent resolution during pull is order-dependent

**Severity:** Medium

Folder pull resolves `parentSyncId` in a single pass against already-loaded folders. If the payload arrives child-before-parent, the child is created without its parent link and there is no repair pass afterward.

- File refs: `Sources/Cider/Services/SyncService.swift`

### CH-C19 — Duplicate external sources are allowed by path

**Severity:** Medium

`ExternalSourceStorage.addSource(path:displayName:)` does not deduplicate on `path`, so the same directory can be added multiple times, creating duplicate source records and duplicate scans.

- File refs: `Sources/Cider/Services/ExternalSourceStorage.swift`

### CH-C20 — `screenCaptureDefaultAction` setting is currently non-functional

**Severity:** Medium

When the screen-capture toast timer expires, `executeScreenCaptureDefaultAction()` is called, but it only dismisses the toast and optionally restores the panel. It does not branch on `CiderConfig.screenCaptureDefaultAction`.

- File refs: `Sources/Cider/App/AppDelegate.swift`, `Sources/Cider/Models/CiderConfig.swift`

---

## Performance

### ~~CH-P06 — CiderConfig.load() decoded on every render in computed properties~~ ✅ Fixed 2026-02-24

`sourceTabs` and `savedViewTabs` computed properties in `CiderPanelView` called `CiderConfig.load()` (UserDefaults decode) on every body evaluation. `FolderSidebarView.body` did the same for `enableLinkedSources`. Fixed: added `@State` properties refreshed via `.onReceive(.ciderConfigChanged)`; `FolderSidebarView` takes `enableLinkedSources` as a parameter.

- File refs: `Sources/Cider/Views/CiderPanelView.swift`, `Sources/Cider/Views/Shared/FolderSidebarView.swift`

### ~~CH-P01 — Main-thread disk I/O in search~~ ✅ Fixed 2026-02-21

`search()` is now `async`. Note content loading extracted to `fetchNoteResults()` — a `nonisolated static async` method that reads files on the cooperative thread pool. `searchNotes()` captures `NotesStorage.shared.notesDirectoryURL` on the main actor then `await`s the nonisolated helper. Both call sites (`SearchPaletteView` task, `SearchTabContent` `.task(id:)`) already run off the main actor. `SearchTabContent` switched from computed property to `@State + .task(id: query)`.

### ~~CH-P02 — Main-thread I/O at startup and directory-switch~~ ✅ Fixed 2026-02-21

**NotesStorage:** `init()` and `updateDirectory()` now capture file URLs on MainActor, fire `Task.detached(priority: .userInitiated)` calling a new `nonisolated static loadAndScan(directoryURL:indexURL:indexFileName:)` that combines `loadIndex` + `scanNotes` I/O off-thread, then applies `(index, notes, needsSave)` back on MainActor. Existing `loadIndex()` and `scanNotes()` instance methods kept for directory watcher.

**BookmarksStorage:** `init()` reads both files (`_cider_bookmarks_metadata.json`, `bookmarks.html`) in `Task.detached`, then parses and applies via new `buildSnapshotFromFiles(metaData:htmlData:)` on MainActor. `load()`, `loadFromDisk()`, and `loadMetadataSnapshot()` unchanged (still used by `updateDirectory()` and `reload()`).

### ~~CH-P03 — Attachment orphan cleanup scans all notes on main actor~~ ✅ Fixed 2026-02-21

`scheduleAttachmentCleanup()` now captures note paths and the attachments directory on MainActor, then fires `Task.detached(priority: .background)` calling `nonisolated static removeOrphanAttachmentsInBackground(notePaths:attachmentsDir:gracePeriodSeconds:)`. `referencedAttachmentFilenamesFromPaths(_:)` and `extractAttachmentFilenames(from:regex:into:)` also made `nonisolated static`. Old instance methods `removeOrphanAttachments()` and `referencedAttachmentFilenames()` removed.

### ~~CH-P04 — Config save thrashing on slider changes~~ ✅ Fixed 2026-02-21

`homeCardSizeScale` onChange in `CiderPanelView` now debounces via a cancelled-and-restarted `Task` with 300ms sleep before saving. `CiderConfig.save()` no longer logs on every call.

### ~~CH-P05 — CiderFont decodes config on every render access~~ ✅ Fixed 2026-02-21

`_cachedScale` (`nonisolated(unsafe) static var`) is set once at startup. `invalidateScale()` re-reads config and updates the cache; called at the top of `AppDelegate.handleConfigChanged()`. Font tokens now read the cached value with no UserDefaults decode per access.

### CH-P07 — SpotlightIndexer duplicates subscriptions on repeated `start()`

**Severity:** Medium

`SpotlightIndexer.start()` always calls `bindStorages()` without guarding against existing subscriptions. Repeated calls while indexing remains enabled stack Combine sinks in `cancellables` and multiply reindex triggers.

- File refs: `Sources/Cider/Services/SpotlightIndexer.swift`, `Sources/Cider/App/AppDelegate.swift`

### CH-P08 — Spotlight reindex still performs blocking disk I/O on the main actor

**Severity:** Medium

`SpotlightIndexer` is `@MainActor`, and `reindexAll()` still reads thumbnail files and note content synchronously during indexing. Larger libraries can stall the UI during reindex cycles.

- File refs: `Sources/Cider/Services/SpotlightIndexer.swift`

---

## Design & Architecture

### ~~CH-D01 — Carbon fallback hotkeys consume keys when disabled~~ ✅ Fixed 2026-02-21

`handleHotKeyEvent` in both `NotesHotkeyDetector` and `BookmarksHotkeyDetector` now returns `OSStatus(eventNotHandledErr)` (not `noErr`) when `isEnabled` is false, so the event passes through to other handlers.

### ~~CH-D02 — Undo-toast hover resets timer instead of pausing~~ ✅ Fixed 2026-02-21

Hover-enter branch now only stops the timer and sets `undoToastIsHovering = true`; `undoToastRemaining` and `undoToastModel.progress` are no longer reset. Hover-exit resumes the timer from where it left off.

### ~~CH-D03 — Non-spring animation curves in panel transitions~~ ✅ Fixed 2026-02-21

Replaced `CAMediaTimingFunction(name: .easeInEaseOut)` with `CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)` (fast-out deceleration curve, perceptually matching a critically-damped spring) in all three panel files. Reduce-motion guard was already present.

### ~~CH-D04 — Search palette uses `.shadow()` instead of shape-based shadow~~ ✅ Fixed 2026-02-21, regressed, re-fixed 2026-02-24

Replaced `.shadow(...)` with `.background { RoundedRectangle.fill(.black).blur(24).offset(y:12).opacity(...) }` — same pattern as `AcrylicPanelBackground`. Regression detected 2026-02-24 (`.shadow()` modifier had returned); re-applied the blurred-shape fix.

### ~~CH-D05 — Some UI elements ignore global text-size preference~~ ✅ Fixed 2026-02-21

Added `CiderFont.scale: CGFloat` public property. Changed `emptyStateIcon` from `static let` to `static var` using `scaled(36)`. Fixed traffic light symbol fonts in `CiderPanelShell.swift` to multiply by `CiderFont.scale`. `appIcon` left as fixed 64pt (purely decorative on About screen). (Note: NotesPanelView and BookmarksPanelView references removed — standalone panels deleted in Feb 2026 consolidation.)

### ~~CH-D06 — Docs index/status drift from implemented product model~~ ✅ Fixed 2026-02-28

Fixed DOCS_INDEX.md linked sources status (🔲 → ✅). Updated QUICK_REFERENCE.md tab status table to reflect F-02 SavedView architecture (no fixed "Bookmarks"/"Notes" tabs).

- File refs: `Docs/DOCS_INDEX.md`, `Docs/QUICK_REFERENCE.md`

### ~~CH-D07 — Missing reduce motion guard in AppDelegate panel expand/restore~~ ✅ Fixed 2026-02-24

`expandCiderPanelForSlideOut` and `restoreCiderPanelAfterSlideOut` used `NSAnimationContext.runAnimationGroup` without checking `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. Added guard to both — when reduce motion is enabled, frame changes apply immediately.

- File refs: `Sources/Cider/App/AppDelegate.swift`

### ~~CH-D08 — Missing reduce motion guard in DateCardDetailView and ContactDetailView~~ ✅ Fixed 2026-02-24

Both views used `withAnimation(.snappy)` without `reduceMotion` check. Added `@Environment(\.accessibilityReduceMotion)` and guarded the animation.

- File refs: `Sources/Cider/Views/DateCards/DateCardDetailView.swift`, `Sources/Cider/Views/Contacts/ContactDetailView.swift`

### ~~CH-D09 — `.contextMenu` in lazy containers: SavedViewTabContent, SourceCardView, FolderSidebarView~~ ✅ Fixed 2026-02-24

7 instances of SwiftUI `.contextMenu` inside `LazyVStack`/`LazyVGrid` replaced with `CardContextMenuModifier` (builds fresh `NSMenu` on each right-click). SavedViewTabContent had data-driven submenus (stacks, contacts) that would cache stale data; now rebuilt at invocation time.

- File refs: `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift`, `Sources/Cider/Views/Sources/SourceCardView.swift`, `Sources/Cider/Views/Shared/FolderSidebarView.swift`

### ~~CH-D10 — Hardcoded font sizes in BookmarkDetailsSheet~~ ✅ Fixed 2026-02-24

Four instances of `.font(.system(size: 8/9))` on small icon elements did not scale with `CiderFont.scale`. Multiplied by `CiderFont.scale` to respect user text-size preference.

- File refs: `Sources/Cider/Views/Bookmarks/BookmarkDetailsSheet.swift`

### ~~CH-D11 — Hardcoded `.foregroundColor(.white)` instead of CiderColors.textOnColor~~ ✅ Fixed 2026-02-24

Three instances of `.foregroundColor(.white)` on text/icons over colored backgrounds replaced with `CiderColors.textOnColor` (`Color.white.opacity(0.9)`).

- File refs: `Sources/Cider/Views/Shared/SelectionCheckmark.swift`, `Sources/Cider/Views/Shared/NewItemPopover.swift`, `Sources/Cider/Views/Shared/FolderDetailView.swift`

### CH-D12 — Spotlight indexing is enabled by default for user content

**Severity:** Medium

`enableSpotlightIndexing` defaults to `true`, which means bookmark notes, note snippets, and contact metadata are published into the system search index unless the user opts out after launch.

- File refs: `Sources/Cider/Models/CiderConfig.swift`, `Sources/Cider/Services/SpotlightIndexer.swift`

### CH-D13 — Clipboard history defaults are too aggressive for sensitive data

**Severity:** Medium

Clipboard history is enabled by default and text retention defaults to `0` (infinite). The app therefore stores copied content persistently unless the user explicitly changes the setting.

- File refs: `Sources/Cider/Models/CiderConfig.swift`, `Sources/Cider/Services/ClipboardStorage.swift`, `Sources/Cider/Services/ClipboardHistoryService.swift`

### CH-D14 — WebView metadata extraction uses persistent website data by default

**Severity:** Low

The headless metadata extraction path still uses a standard `WKWebViewConfiguration` with shared process state instead of an ephemeral website data store, increasing cookie/storage bleed across enrichment runs.

- File refs: `Sources/Cider/Services/WebViewMetadataExtractor.swift`

### CH-D15 — `AppDelegate` remains a high-coupling coordinator

**Severity:** Low

`AppDelegate.swift` is still responsible for hotkeys, panel lifecycle, sync startup, Spotlight, clipboard viewer flow, screen-capture routing, notifications, and multiple toast/timer state machines. The file remains a large coordination bottleneck and raises regression risk for unrelated changes.

- File refs: `Sources/Cider/App/AppDelegate.swift`

---

## Dead Code & Cleanup

### ~~CH-L01 — Stale feature flags with no runtime gating~~ ✅ Fixed 2026-02-21

`enableDateCards`, `enableStacks`, `enableCalendarProjection` removed from `CiderConfig` (CodingKeys, var declarations, `default`, memberwise `init`, `init(from:)`). `enableSavedViewTabs` and `enableLinkedSources` kept — both actively gate behavior in `CiderPanelView` and `FolderSidebarView`.

### ~~CH-L02 — Dead code artifacts~~ ✅ Fixed 2026-02-21

`SystemStatus.swift` and `FeatureSettings.swift` deleted (confirmed zero references). `ProjectTabContent.swift:16` reported as unused import was a false positive — only `import SwiftUI` exists at line 1 and is used; no change needed.

### ~~CH-L03 — Legacy tab/browser views appear unreferenced after panel consolidation~~ ✅ Fixed 2026-02-25

Deleted 6 dead view files, 2 dormant subsystem files, and 1 unused utility. Extracted `BookmarkThumbnailView` and `BookmarkVisualStyle` to their own files before deleting `BookmarksBrowserView.swift`. Stripped `AccessibilityHelpers.swift` to only `promptIfNeeded()`. Pruned ~70 dead constants from `Constants.swift`. Removed dead `LibraryItem` V1 enum. Converted `print()` to `Logger` in 4 files. See "Removed Code Archive" section for full inventory.

### ~~CH-L04 — Persistent SPM warning for unhandled resources~~ ✅ Fixed 2026-02-28

Added `Info.plist`, `menubar-icon.png`, and `cider-icon.png` to `exclude:` list in `Package.swift`. These resources are bundled by the Xcode project; SPM build is for compilation verification only.

- File refs: `Package.swift`

---

## Resolved

### ✅ HI-02 — Test suite failed to compile (TileNode / SplitOrientation)

Stale tests from the window-manager era referenced removed types. Resolved when the window management pivot cleaned out these modules.

- Fixed: 2026-02

### ✅ LO-01 — SQLite doc drift

Docs previously described SQLite metadata storage; implementation is file/JSON-based. Documentation updated to reflect actual architecture.

- Fixed: 2026-02

---

## Removed Code Archive

> **Purpose:** Paper trail of intentionally deleted code. If you want to resurrect anything here, check `git log` for the last commit containing it.

### 2026-02-25 — Dead Code Cleanup

#### Deleted View Files

| File | What It Was | Why Removed |
|---|---|---|
| `Views/Notes/NotesTabContent.swift` | Standalone Notes tab wrapper that instantiated NotesBrowserView | Superseded by Home tab + Saved View architecture; zero call sites |
| `Views/Notes/NotesBrowserView.swift` | Notes browsing view with display modes, search, masonry/grid/list | Only caller was dead NotesTabContent; all functionality now lives in HomeDashboardView + FolderDetailView + SavedViewTabContent |
| `Views/Shared/FolderContentView.swift` | Basic folder content list (bookmarks + notes rows) | Superseded by FolderDetailView which adds rich cards, masonry, sticky headers |
| `Views/Shared/RootFolderOverviewView.swift` | Root folder overview with sub-folder cards and unsorted items | Superseded by FolderDetailView |
| `Views/Bookmarks/BookmarksBrowserView.swift` | Standalone Bookmarks browser with display modes, drag-drop, toolbar | Superseded by Home + SavedView architecture. `BookmarkThumbnailView` and `BookmarkVisualStyle` were extracted to their own files before deletion. |
| `Utilities/PopoverAnchorView.swift` | NSViewRepresentable for manual NSPopover positioning | Documented as broken in non-activating panels (CLAUDE.md); SwiftUI `.popover()` used everywhere instead |

#### Deleted Dormant Subsystems

| Files | What It Was | Why Removed |
|---|---|---|
| `Services/ProjectStorage.swift` + `Models/Project.swift` | Full CRUD storage for Projects feature (create, rename, archive, add items) | `.project` CiderTab case was removed; no UI references Projects; only `reload()` was called from AppDelegate |

#### Stripped Down: AccessibilityHelpers.swift

Removed 16+ unused AX window-management methods (appElement, windows, title, windowID, isMinimized, get/setWindowPosition, get/setWindowSize, get/setEnhancedUI, isFullScreen, exitFullScreen, coordinate converters, private `_AXUIElementGetWindow` SPI). These were from the original window-tiling feature. Only `promptIfNeeded()` (and its internal helpers `isTrusted`/`promptForTrust`) retained.

#### Deleted Dead Types

| Location | Type | What It Was |
|---|---|---|
| `Models/LibraryDisplayMode.swift` | `enum LibraryItem` | V1 discriminated union (.bookmark/.note). Fully superseded by `LibraryItemV2` which adds .dateCard, .contact, .externalFile |

#### Pruned Constants (Constants.swift)

| Removed | What It Was |
|---|---|
| `enum CiderDesign` (7 constants) | Generic design tokens (cornerRadius, componentSpacing, iconSize, etc.) — never referenced; views use Radius/Spacing tokens directly |
| `CiderAnimation.smooth/.bouncy/.reduceMotion/.hoverMagnify/.listReorder` | Animation presets — code uses SwiftUI's `.smooth`/`.bouncy` directly; only `.snappy` was referenced |
| `BookmarksDesign` panel/shelf/flyout/detail-sheet groups (~35 constants) | Sizing for standalone bookmarks panel, folder shelf UI, folder flyout menus, detail sheet — all from pre-consolidation architecture |
| `NotesDesign` panel sizing group (~13 constants) | Sizing for standalone notes panel — now inline in CiderPanel |
| `SearchPaletteDesign.paletteMaxHeight/.backdropOpacity/.paletteVerticalOffset` | Unused palette sizing constants |
| `.showBookmarkAddForm` notification | Never posted anywhere — observer existed in dead BookmarksBrowserView |
| `.triggerNewNoteInTab` notification | Never posted or observed |
| `.screenCaptureComplete` notification | Never posted or observed — screen capture flow uses toast model directly |

#### Other Cleanup

| Change | Detail |
|---|---|
| `print()` → `Logger` in hotkey detectors | BookmarksHotkeyDetector, NotesHotkeyDetector, ScreenCaptureHotkeyDetector — `print()` goes to stdout (invisible at runtime); converted to os.Logger |
| `print()` → `Logger` in SettingsViewModel | SMAppService error logging |
| `"cider.openExternalFile"` → typed constant | Raw string literal used in 7+ files; now `.openExternalFile` in Constants.swift |
| Renamed `BookmarkDetailsSheet.swift` → `BookmarkDetailsDraft.swift` | File contains `BookmarkDetailsDraft`, `BookmarkMetadataSidebar`, `BookmarkDetailsHeroPreview` — not a "details sheet" |
