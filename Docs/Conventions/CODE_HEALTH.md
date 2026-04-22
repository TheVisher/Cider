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

### CH-S05 — Sync token handling is only partially hardened — Won't fix (backward compat)

**Severity:** Low (downgraded from High — HTTPS enforcement added in CH-S12)

The sync token lives in Keychain and the migration clears it from UserDefaults. The vestigial `syncToken` property remains in `CiderConfig` to avoid breaking existing configs that include the key — it always decodes to empty string post-migration. HTTPS is now enforced by CH-S12. Removing the property entirely would require a breaking config migration for no security gain.

- File refs: `Sources/Cider/Models/CiderConfig.swift`, `Sources/Cider/Services/KeychainHelper.swift`

### ~~CH-S06 — Bookmark enrichment leaks full page URL via `Referer` and public logs~~ ✅ Fixed 2026-03-13

Referer header now sends only the origin (`scheme://host/`) instead of the full page URL, preventing query params and path tokens from leaking to image hosts. Error logs redacted from full URL to host-only.

- File refs: `Sources/Cider/Services/BookmarksStorage.swift`

### CH-S07 — Clipboard URL favicon fetch leaks copied domains to third parties — By design

**Severity:** Low (downgraded — fetching favicons inherently requires contacting a server)

Favicon fetching is a core feature of the clipboard viewer — URL cards show site icons. The favicon sources (DuckDuckGo, Google, direct) are well-known CDNs. Disabling would degrade the clipboard viewer UX. Could add a user toggle if privacy-sensitive users request it.

- File refs: `Sources/Cider/Services/ClipboardStorage.swift`

### ~~CH-S08 — Reader extraction executes untrusted page JavaScript during preload~~ ✅ Fixed 2026-03-13

Fetched HTML is now stripped of all `<script>` tags before being loaded into the extraction `WKWebView`. Readability.js is injected separately via `evaluateJavaScript` after load, so it still works. Untrusted page scripts no longer execute during preload.

- File refs: `Sources/Cider/Services/DetailWebViewStore.swift`

### ~~CH-S09 — Reader mode renders extracted article fields as trusted HTML~~ ✅ Fixed 2026-03-13

`BookmarkReaderView` now HTML-escapes `article.title` and `article.byline` before interpolation into the reader template. `article.content` is left as-is since it's sanitized HTML from Readability.js meant to render as HTML.

- File refs: `Sources/Cider/Views/Bookmarks/BookmarkReaderView.swift`

### ~~CH-S10 — Editor and whiteboard webviews still expose the entire home directory to local web content~~ ✅ Fixed 2026-03-13

`allowingReadAccessTo` in both `NotesViewModel` and `WhiteboardViewModel` changed from `NSHomeDirectory()` to `StoragePaths.cachedVaultDirectoryURL` — the vault directory where notes, attachments, and whiteboards actually live.

- File refs: `Sources/Cider/ViewModels/NotesViewModel.swift`, `Sources/Cider/ViewModels/WhiteboardViewModel.swift`

### ~~CH-S11 — External URL launches are not scheme-restricted~~ ✅ Fixed 2026-03-13

Added `openURLSafely()` utility that only allows `http`/`https` schemes. Applied to all webview navigation delegates handling untrusted content: `BookmarkReaderView`, `BookmarkWebView`, and `TipTapEditorView` (link clicks and navigation). `DetailWebViewStore`'s preload delegate intentionally omits `decidePolicyFor` — it blocks new windows via `SuppressingUIDelegate` instead. User-initiated "Open in Browser" actions from trusted UI buttons are unchanged.

- File refs: `Sources/Cider/Utilities/Constants.swift`, `Sources/Cider/Views/Bookmarks/BookmarkReaderView.swift`, `Sources/Cider/Views/Bookmarks/BookmarkWebView.swift`, `Sources/Cider/Views/Notes/TipTapEditorView.swift`

### ~~CH-S12 — Sync endpoint validation is still missing before token use~~ ✅ Fixed 2026-03-13

`SyncService.startIfEnabled()` now enforces that `syncURL` starts with `https://` before deriving the deployment URL or sending the sync token. Non-HTTPS URLs are rejected with a log error and sync is stopped.

- File refs: `Sources/Cider/Services/SyncService.swift`

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

### ~~CH-C15 — `NotesStorage.updateDirectory` still breaks synchronous callers and regression test~~ ✅ Fixed 2026-03-08

`updateDirectory(to:)` now calls `loadAndScan` synchronously instead of spawning an unawaited async `Task`. Notes and index are populated before the method returns. The async path is kept only for `init()` (startup) where background loading avoids blocking app launch. The regression test now passes since `storage.notes.count` reflects the scanned state immediately.

- File refs: `Sources/Cider/Services/NotesStorage.swift`

### ~~CH-C16 — Dirty-only sync can miss bookmark folder moves~~ ✅ Fixed 2026-03-08

`BookmarksStorage.assignBookmark(_:toFolder:)` now bumps `updatedAt` to `Date()` before calling `persist()`, so the dirty-only push filter in `SyncService` includes folder reassignments.

- File refs: `Sources/Cider/Services/BookmarksStorage.swift`

### ~~CH-C17 — Sync stop/reconfigure does not cancel in-flight work~~ ✅ Fixed 2026-03-13

`SyncService.stop()` now cancels the auth task, push debounce task, and pull debounce task. The auth flow checks `Task.isCancelled` before proceeding after authentication.

- File refs: `Sources/Cider/Services/SyncService.swift`

### CH-C18 — Folder parent resolution during pull is order-dependent — Deferred (sync protocol)

**Severity:** Medium

Folder pull resolves `parentSyncId` in a single pass against already-loaded folders. If the payload arrives child-before-parent, the child is created without its parent link and there is no repair pass afterward. Fix requires coordination with Cider Web and iOS sync implementations.

- File refs: `Sources/Cider/Services/SyncService.swift`

### ~~CH-C19 — Duplicate external sources are allowed by path~~ ✅ Fixed 2026-03-13

`ExternalSourceStorage.addSource()` now checks for an existing source with the same path and returns it instead of creating a duplicate.

- File refs: `Sources/Cider/Services/ExternalSourceStorage.swift`

### CH-C21 — Web/iOS-created items without `ciderSyncId` are skipped on desktop pull — Deferred (sync protocol)

**Severity:** Medium

Bookmarks, folders, and notes created on Cider Web or Cider iOS that lack a `ciderSyncId` are silently skipped by the desktop `applyPullResult()`. Fix requires changes to the Convex backend (`sync.ts`) to auto-assign syncIds, or desktop-side UUID generation. Needs coordination with web/iOS development.

- File refs: `Sources/Cider/Services/SyncService.swift`, `Cider-Web/convex/sync.ts`

### ~~CH-C22 — Note editor sandboxing broke local attachment rendering~~ ✅ Fixed 2026-03-21

Vault images are now served via a `cider-vault://` custom URL scheme (`CiderVaultSchemeHandler`), bypassing the `allowingReadAccessTo` constraint. `NotesMarkdownPathCodec` rewrites attachment paths to `cider-vault:///absolute/path` URLs, and the editor's `WKWebView` is configured with the scheme handler. This lets the editor sandbox `file://` access to only the TipTapEditor bundle while still rendering vault attachments.

- File refs: `Sources/Cider/Services/CiderVaultSchemeHandler.swift`, `Sources/Cider/Services/NotesMarkdownPathCodec.swift`, `Sources/Cider/ViewModels/NotesViewModel.swift`

### ~~CH-C23 — Sync-driven note deletes bypass orphan attachment cleanup~~ ✅ Fixed 2026-04-22

**Severity:** Medium

`deleteFromSync(_:)` now routes through `delete(note:trackSync:)`, which already schedules orphan attachment cleanup after removing the note from disk, snapshots, and SQLite. The prior review note was stale.

- File refs: `Sources/Cider/Services/NotesStorage.swift`

### ~~CH-C20 — `screenCaptureDefaultAction` setting is currently non-functional~~ Deferred (design decision)

The setting exists in CiderConfig but has no UI and no implementation. Auto-executing an action (create note/dateCard/contact) on toast timeout would be surprising behavior — the 8-second timeout gives users time to choose. The setting is kept for potential future use but intentionally not wired up.

- File refs: `Sources/Cider/App/AppDelegate+ScreenCapture.swift`, `Sources/Cider/Models/CiderConfig.swift`

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

### ~~CH-P07 — SpotlightIndexer duplicates subscriptions on repeated `start()`~~ ✅ Fixed 2026-03-13

`SpotlightIndexer.start()` now clears existing subscriptions (`cancellables.removeAll()`) and cancels the debounce task before re-binding, preventing stacked subscriptions.

- File refs: `Sources/Cider/Services/SpotlightIndexer.swift`

### ~~CH-P08 — Spotlight reindex still performs blocking disk I/O on the main actor~~ ✅ Fixed 2026-03-13

`SpotlightIndexer.reindexAll()` now loads thumbnail data off the main thread via `Task.detached(priority: .utility)`, then builds and submits index items back on the main actor.

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

Fixed DOCS_INDEX.md linked sources status (🔲 → ✅). Updated QUICK_REFERENCE.md tab status table to reflect F-02 SavedView architecture (no fixed "Bookmarks"/"Notes" tabs). (Note: both files have since been deleted as part of docs restructuring.)

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

- File refs: `Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift`

### ~~CH-D11 — Hardcoded `.foregroundColor(.white)` instead of CiderColors.textOnColor~~ ✅ Fixed 2026-02-24

Three instances of `.foregroundColor(.white)` on text/icons over colored backgrounds replaced with `CiderColors.textOnColor` (`Color.white.opacity(0.9)`).

- File refs: `Sources/Cider/Views/Shared/SelectionCheckmark.swift`, `Sources/Cider/Views/Shared/NewItemPopover.swift`, `Sources/Cider/Views/Shared/FolderDetailView.swift`

### ~~CH-D12 — Spotlight indexing is enabled by default for user content~~ ✅ Fixed 2026-03-13

`enableSpotlightIndexing` default changed from `true` to `false`. Users must opt in via Settings. Existing users who already have the setting saved are unaffected.

- File refs: `Sources/Cider/Models/CiderConfig.swift`

### ~~CH-D13 — Clipboard history defaults are too aggressive for sensitive data~~ ✅ Fixed 2026-03-13

`clipboardRetentionDays` default changed from `0` (infinite) to `30` days. Users can still set it to 0 for infinite retention via Settings. Existing users who already have the setting saved are unaffected.

- File refs: `Sources/Cider/Models/CiderConfig.swift`

### ~~CH-D14 — WebView metadata extraction uses persistent website data by default~~ ✅ Fixed 2026-03-13

`WebViewMetadataExtractor` now uses `.nonPersistent()` website data store so cookies and storage from one extraction don't persist or leak into subsequent runs.

- File refs: `Sources/Cider/Services/WebViewMetadataExtractor.swift`

### CH-D16 — List view and display modes are inconsistent across card types

**Severity:** Medium

Source detail views don't respond well to view option changes (grid, masonry, list). List view in particular needs significant work and standardization across ALL card types — bookmarks, notes, contacts, todos, date cards, and sources each have inconsistent list row layouts. Need a shared `ListRowContainer` pattern with consistent column alignment, hover states, and information density. Grid and masonry modes also have minor inconsistencies between card types.

- File refs: `Sources/Cider/Views/Sources/SourceDetailView.swift`, `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift`, `Sources/Cider/Views/Shared/FolderDetailView.swift`

### CH-D17 — “Per-display” panel position memory is keyed only by resolution

**Severity:** Medium

The new panel-position persistence uses only backing pixel dimensions as the per-screen key. Two identical monitors therefore overwrite each other's saved frame, so the feature is not actually per-display on common multi-monitor setups.

- File refs: `Sources/Cider/Services/CiderPanelPositionStore.swift`, `Sources/Cider/App/AppDelegate.swift`

### ~~CH-D18 — `Docs/ARCHITECTURE.md` no longer matches the current panel and sync architecture~~ Resolved

**Severity:** Low

The architecture reference previously described removed UI concepts (Projects section, `BookmarksTabContent`, `NotesTabContent`) and the old bookmark-only REST polling sync model. `Docs/ARCHITECTURE.md` has now been updated to reflect the current saved-view/source tab model and Convex-based sync for bookmarks, folders, and notes.

- File refs: `Docs/ARCHITECTURE.md`, `Sources/Cider/Views/CiderPanelView.swift`, `Sources/Cider/Services/SyncService.swift`

### CH-D15 — `AppDelegate` remains a high-coupling coordinator — Mitigated

**Severity:** Low

AppDelegate was split into 5 focused extension files (Toasts, CiderPanel, ScreenCapture, ClipboardPanel, AIAssistantPanel) in March 2026. The main file is now ~600 lines. The responsibilities are still coordinated through AppDelegate, but the extension split reduces regression risk and improves navigability. Further extraction into standalone services is possible but not warranted at current scale.

- File refs: `Sources/Cider/App/AppDelegate.swift`, `Sources/Cider/App/AppDelegate+*.swift`

---

## Dead Code & Cleanup

### ~~CH-L01 — Stale feature flags with no runtime gating~~ ✅ Fixed 2026-02-21

`enableDateCards`, `enableStacks`, `enableCalendarProjection` removed from `CiderConfig` (CodingKeys, var declarations, `default`, memberwise `init`, `init(from:)`). `enableLinkedSources` kept — actively gates behavior in `FolderSidebarView`. (`enableSavedViewTabs` was also kept at the time but has since been removed.)

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

---

## Weekly Code Health Scan — 2026-03-15

### Summary

| Metric | Desktop | iOS | Web | Total |
|---|---|---|---|---|
| Source files | 228 (.swift) | 48 (.swift) | 103 (.ts/.tsx/.js) | 379 |
| Lines of code | 61,710 | 10,546 | 15,830 | 88,086 |
| TODO comments | 0 | 0 | 0 | 0 |
| FIXME comments | 0 | 0 | 0 | 0 |
| HACK comments | 0 | 0 | 0 | 0 |
| Files >500 lines | 32 | 5 | 7 | 44 |
| TypeScript errors | — | — | 0 | 0 |
| Swift build | N/A (no toolchain) | N/A | — | — |

### TODO/FIXME/HACK Comments

All three repos are clean — zero actionable TODO, FIXME, or HACK comments in project-owned source code. (Desktop's `ICalendarSerializer.swift` and `TodoCardStorage.swift` contain `VTODO`/`TodoCard` references which are iCalendar protocol terms, not code health markers.)

### TypeScript Health (Cider-Web)

`tsc --noEmit` passes with zero errors. The web codebase is type-clean.

### Large Files Needing Attention

Files over 500 lines are candidates for decomposition. **32 files exceed the threshold on Desktop** (up from 19 in the prior scan — 13 newly crossed the line, likely from incremental feature work). iOS and Web are stable.

**Desktop — 32 files >500 lines (top concerns):**

| File | Lines | Suggested Action |
|---|---|---|
| `Services/BookmarksStorage.swift` | 2,418 | **Critical.** Extract import/export codecs, enrichment logic, and folder operations into focused files. |
| `Views/Notes/InlineNoteEditorView.swift` | 1,390 | Extract toolbar, formatting helpers, and drag-drop handling. |
| `Views/SavedViews/SavedViewTabContent.swift` | 1,332 | Extract card/row builders per entity type into shared components. |
| `Views/Shared/FolderSidebarView.swift` | 1,319 | Extract folder tree rendering and drag-drop logic. |
| `Services/NotesStorage.swift` | 1,287 | Extract scan/index logic, attachment cleanup, and sync helpers. |
| `ViewModels/NotesViewModel.swift` | 1,242 | Extract WebView bridge, HTML generation, and attachment handling. |
| `Views/Shared/FolderDetailView.swift` | 1,227 | Extract grid/masonry/list renderers. |
| `Views/Shared/NewItemPopover.swift` | 1,136 | Extract individual item-creation cards. |
| `Views/Bookmarks/BookmarkDetailsDraft.swift` | 1,047 | Extract `BookmarkMetadataSidebar` and `BookmarkDetailsHeroPreview` to own files. |
| `Services/SyncService.swift` | 950 | Extract push/pull/auth into sub-services. |
| `Views/Search/SearchPaletteView.swift` | 940 | Extract result renderers per entity type. |
| `Views/Home/HomeDashboardView.swift` | 874 | Extract section renderers (recent, pinned, etc.). |
| `Views/Shared/ClipboardViewerView.swift` | 829 | Extract item renderers and filter logic. |
| `Services/VaultFolderService.swift` | 815 | Extract migration and validation helpers. |
| `Views/Shared/TagDetailView.swift` | 747 | Extract tag editing and assignment UI. |
| `Views/Settings/SettingsComponents.swift` | 719 | Extract reusable setting row types. |
| `Models/CiderConfig.swift` | 691 | Extract nested config types or use sub-configs. |
| `Services/TrashStorage.swift` | 672 | Extract restore logic and manifest management. |
| `Services/ActiveBrowserCaptureService.swift` | 660 | Extract browser-specific capture adapters. |
| `Services/BookmarkMetadataParser.swift` | 605 | *New.* Extract per-format parsers (Open Graph, Twitter Card, etc.). |
| `Views/Bookmarks/BookmarkThumbnailView.swift` | 602 | *New.* Extract thumbnail layout variants. |
| `Services/SearchService.swift` | 585 | *New.* Extract per-entity search logic. |
| `Views/Stacks/StackManagerSheet.swift` | 583 | *New.* Extract stack item renderers. |
| `App/AppDelegate.swift` | ~600 | Already split into extensions (CH-D15). Monitor but acceptable. |
| `Services/VaultStructureMigration.swift` | 561 | *New.* Extract per-version migration steps. |
| `Views/Settings/SettingsView+SubcategoryContent.swift` | 554 | *New.* Extract individual subcategory views. |
| `Services/ContactStorage.swift` | 537 | *New.* Extract vCard serialization. |
| `Services/TodoCardStorage.swift` | 531 | *New.* Extract iCal serialization (shared with ICalendarSerializer). |
| `Views/Shared/DetailSlideOutView.swift` | 522 | *New.* Extract slide-out animation and layout logic. |
| `Views/CiderPanelView+DetailViews.swift` | 514 | *New.* Extract per-entity detail view builders. |
| `Views/Notes/TipTapEditorView.swift` | 510 | *New.* Extract bridge message handling. |
| `Utilities/Constants.swift` | 504 | *New.* Extract domain-specific constant groups into their own files. |

**iOS — 5 files >500 lines (unchanged):**

| File | Lines | Suggested Action |
|---|---|---|
| `Views/BookmarkListView.swift` | 939 | Extract row builders and filter logic. |
| `Views/BookmarkDetailView.swift` | 725 | Extract metadata sections. |
| `Views/SidebarView.swift` | 614 | Extract navigation items and folder tree. |
| `Views/FolderBrowserView.swift` | 605 | Extract folder card components. |
| `Views/NoteEditorToolbar.swift` | 546 | Extract formatting button groups. |

**Web — 7 files >500 lines (unchanged):**

| File | Lines | Suggested Action |
|---|---|---|
| `components/bookmarks/bookmark-detail.tsx` | 1,080 | Extract metadata panel, action bar, and reader sub-components. |
| `components/landing/landing-page.tsx` | 844 | Extract individual landing sections. |
| `components/layout/sidebar.tsx` | 812 | Extract nav groups and folder tree. |
| `components/notes/note-editor.tsx` | 770 | Extract toolbar and formatting helpers. |
| `components/notes/note-detail.tsx` | 592 | Extract metadata sidebar. |
| `components/bookmarks/library-table-view.tsx` | 592 | Extract column renderers and sort logic. |
| `convex/syncInternal.ts` | 504 | Extract push/pull handlers into separate modules. |

### Trend vs. Prior Scan

This is the first automated scan, so no prior-scan comparison is available. The numbers above establish the baseline for future delta tracking.

### Open Issues from Previous Reviews

These items remain unresolved from prior code reviews:

| ID | Severity | Summary |
|---|---|---|
| CH-C18 | Medium | Folder parent resolution during pull is order-dependent (deferred — sync protocol) |
| CH-C21 | Medium | Web/iOS-created items without `ciderSyncId` skipped on desktop pull (deferred — sync protocol) |
| CH-D16 | Medium | List view and display modes inconsistent across card types |
| CH-D17 | Medium | Per-display panel position memory keyed only by resolution |

**Priority recommendations:**

1. **No open High-severity items.** CH-C22 was resolved via the `cider-vault://` scheme handler.
2. **Large file growth on Desktop** — 13 files newly crossed the 500-line threshold. `BookmarksStorage.swift` at 2,418 lines remains the most critical decomposition target. Consider a focused refactoring sprint to extract codecs, parsers, and per-entity builders before these files grow further.

---

## Weekly Code Health Scan — 2026-03-22

### Summary

| Metric | Desktop | iOS | Web | Total |
|---|---|---|---|---|
| Source files | 239 (.swift) | 51 (.swift) | 86 (.ts/.tsx/.js) | 376 |
| Lines of code | 68,507 | 11,620 | 16,058 | 96,185 |
| TODO comments | 0 | 0 | 0 | 0 |
| FIXME comments | 0 | 0 | 0 | 0 |
| HACK comments | 0 | 0 | 0 | 0 |
| Files >500 lines | 38 | 5 | 7 | 50 |
| TypeScript errors | — | — | 0 | 0 |
| Swift build | N/A (no toolchain) | N/A | — | — |

### Trend vs. Prior Scan (2026-03-15)

| Metric | Prior | Current | Delta |
|---|---|---|---|
| Desktop files | 228 | 239 | +11 |
| Desktop LOC | 61,710 | 68,507 | +6,797 |
| Desktop >500L files | 32 | 38 | **+6** |
| iOS files | 48 | 51 | +3 |
| iOS LOC | 10,546 | 11,620 | +1,074 |
| iOS >500L files | 5 | 5 | — |
| Web files | 103 | 86 | -17 |
| Web LOC | 15,830 | 16,058 | +228 |
| Web >500L files | 7 | 7 | — |
| Total LOC | 88,086 | 96,185 | **+8,099** |
| Total >500L files | 44 | 50 | **+6** |

The codebase grew ~9.2% in one week — almost entirely on Desktop (+6,797 LOC). Desktop's large-file count jumped from 32 to 38, continuing the trend noted last scan.

### TODO/FIXME/HACK Comments

All three repos remain clean — zero actionable TODO, FIXME, or HACK comments in project-owned source code.

### TypeScript Health (Cider-Web)

`tsc --noEmit` passes with zero errors. The web codebase remains type-clean.

### Convention Violations

#### Desktop — Force Unwraps (4 instances)

| File | Line | Code | Risk |
|---|---|---|---|
| `Views/Shared/MasonryLayout.swift` | 106 | `columnHeights.enumerated().min(...)!.offset` | Low — array guaranteed non-empty |
| `Services/SyncService.swift` | 953 | `URL(string: "\(siteURL)/api/sync/note-attachments-check")!` | Medium — interpolated URL could fail |
| `Services/SyncService.swift` | 994 | `URL(string: "\(siteURL)/api/sync/upload-note-attachment")!` | Medium — same pattern |
| `Services/VaultFolderService.swift` | 524 | `index[folderID]!` | Low — safe after index write on line 518 |

#### iOS — Force Unwraps (9 instances)

| File | Line | Code | Risk |
|---|---|---|---|
| `Views/BookmarkReaderView.swift` | 26, 28 | `URL(string: bookmark.urlString)!` | **High** — user-supplied URL string |
| `CiderApp.swift` | 109 | `UserDefaults(suiteName: "group.com.cider.app")!` | Medium — suite init can fail |
| `Shared/CiderTab.swift` | 69 | `UserDefaults(suiteName: "group.com.cider.app")!` | Medium — same pattern |
| `Views/SidebarView.swift` | 380 | `icon.unicodeScalars.first!.isASCII` | Low — guarded by prior check |
| `Views/TabChipBar.swift` | 90 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Views/FolderSheetView.swift` | 251 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Views/FolderBrowserView.swift` | 209 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Shared/MasonryLayout.swift` | 70 | `columnHeights.enumerated().min(...)!.offset` | Low — array guaranteed non-empty |

#### iOS — print() Statements (4 instances)

All in `Shared/SyncClient.swift` — should use `os.Logger`:

| Line | Statement |
|---|---|
| 49 | `print("[Cider Raw Pull] \(rawWithNotes.count)/\(bookmarks.count) bookmarks have notes in raw JSON")` |
| 51 | `print("  - \"\(b["title"] ?? "?")\": notes=\"\(b["notes"] ?? "?")\"" )` |
| 61 | `print("[Cider Pull] \(withNotes.count) bookmarks have notes:")` |
| 63 | `print("  - \"\(b.title)\": notes=\"\(b.notes ?? "")\""` |

#### Web — Console Statements (5 instances)

| File | Line | Type | Verdict |
|---|---|---|---|
| `components/error-boundary.tsx` | 25 | `console.error` | Acceptable — error boundary |
| `components/providers/convex-provider.tsx` | 32 | `console.warn` | Acceptable — connection warning |
| `components/notes/note-editor.tsx` | 533 | `console.log` | **Remove** — debug log left in |
| `components/bookmarks/bookmark-capture.tsx` | 61 | `console.warn` | Acceptable — error handling |
| `convex/enrichment.ts` | 73 | `console.error` | Acceptable — server-side error |

#### Web — Type Safety Bypasses (30 `as any` / `as unknown`)

14 in frontend components, 10 in convex backend, 6 in generated route tree. Most common patterns:
- Tiptap editor storage casting (`editor.storage as any`)
- Auth user object assertions in `convex/nativeAuth.ts`
- Polymorphic list rendering in `bookmark-feed.tsx`

### Large Files Needing Attention

**Desktop — 38 files >500 lines** (up from 32 — 6 newly crossed the threshold):

| File | Lines | Delta vs. Prior | Status |
|---|---|---|---|
| `Services/BookmarksStorage.swift` | 2,601 | +183 | **Critical.** Continued growth — decomposition overdue. |
| `Views/Notes/InlineNoteEditorView.swift` | 1,390 | — | Unchanged |
| `Views/SavedViews/SavedViewTabContent.swift` | 1,344 | +12 | |
| `Views/Shared/FolderSidebarView.swift` | 1,319 | — | |
| `Services/NotesStorage.swift` | 1,305 | +18 | |
| `ViewModels/NotesViewModel.swift` | 1,258 | +16 | |
| `Views/Shared/FolderDetailView.swift` | 1,249 | +22 | |
| `Services/AI/AIAssistantTools.swift` | 1,241 | — | *New.* AI tool definitions — extract per-tool handlers. |
| `Views/Shared/NewItemPopover.swift` | 1,136 | — | |
| `Views/Bookmarks/BookmarkDetailsDraft.swift` | 1,073 | +26 | |
| `Services/SyncService.swift` | 1,055 | +105 | **Crossed 1,000 lines.** Extract push/pull/auth sub-services. |
| `Views/Search/SearchPaletteView.swift` | 1,002 | +62 | **Crossed 1,000 lines.** Extract result renderers per entity type. |
| `Utilities/Constants.swift` | 911 | +407 | **Major growth.** Extract domain-specific constant groups. |
| `Views/Home/HomeDashboardView.swift` | 898 | +24 | |
| `Views/Shared/ClipboardViewerView.swift` | 829 | — | |
| `Services/VaultFolderService.swift` | 815 | — | |
| `Services/AI/MLXToolExecutor.swift` | 774 | — | *New.* AI model execution — extract per-model adapters. |
| `Views/Shared/TagDetailView.swift` | 747 | — | |
| `Services/TrashStorage.swift` | 731 | +59 | |
| `Views/Settings/SettingsComponents.swift` | 719 | — | |
| `Models/CiderConfig.swift` | 700 | +9 | |
| `Services/ActiveBrowserCaptureService.swift` | 649 | -11 | Slight reduction |
| `Views/Bookmarks/BookmarkThumbnailView.swift` | 616 | +14 | |
| `Services/SearchService.swift` | 615 | +30 | |
| `Services/BookmarkMetadataParser.swift` | 605 | — | |
| `App/AppDelegate.swift` | 599 | ~0 | Already split into extensions (CH-D15). |
| `Views/Stacks/StackManagerSheet.swift` | 583 | — | |
| `Views/Settings/SettingsView+SubcategoryContent.swift` | 564 | +10 | |
| `Services/VaultStructureMigration.swift` | 561 | — | |
| `Services/ContactStorage.swift` | 537 | — | |
| `Services/TodoCardStorage.swift` | 531 | — | |
| `Views/Shared/DetailSlideOutView.swift` | 530 | +8 | |
| `Views/Notes/TipTapEditorView.swift` | 525 | +15 | |
| `Views/Kanban/KanbanBoardView.swift` | 520 | — | *New.* Kanban board — extract card renderers and drag logic. |
| `Views/Shared/ViewOptionsDropdown.swift` | 519 | — | *New.* View options — extract per-option sections. |
| `Views/CiderPanelView+DetailViews.swift` | 517 | +3 | |
| `Views/AIAssistant/AIAssistantPanelView.swift` | 508 | — | *New.* AI assistant UI — extract message renderers. |

**New files crossing 500 lines since last scan:** `AIAssistantTools.swift` (1,241), `MLXToolExecutor.swift` (774), `KanbanBoardView.swift` (520), `ViewOptionsDropdown.swift` (519), `AIAssistantPanelView.swift` (508). The AI feature area accounts for 3 of the 6 new large files.

**iOS — 5 files >500 lines (unchanged):**

| File | Lines | Suggested Action |
|---|---|---|
| `Views/BookmarkListView.swift` | 939 | Extract row builders and filter logic. |
| `Views/BookmarkDetailView.swift` | 725 | Extract metadata sections. |
| `Views/SidebarView.swift` | 614 | Extract navigation items and folder tree. |
| `Views/FolderBrowserView.swift` | 605 | Extract folder card components. |
| `Views/NoteEditorToolbar.swift` | 546 | Extract formatting button groups. |

**Web — 7 files >500 lines (unchanged count, minor line changes):**

| File | Lines | Delta | Suggested Action |
|---|---|---|---|
| `components/bookmarks/bookmark-detail.tsx` | 1,080 | — | Extract metadata panel, action bar, and reader sub-components. |
| `components/landing/landing-page.tsx` | 844 | — | Extract individual landing sections. |
| `components/layout/sidebar.tsx` | 814 | +2 | Extract nav groups and folder tree. |
| `components/notes/note-editor.tsx` | 772 | +2 | Extract toolbar and formatting helpers. |
| `convex/syncInternal.ts` | 655 | +151 | **Notable growth.** Extract push/pull handlers into separate modules. |
| `components/notes/note-detail.tsx` | 599 | +7 | Extract metadata sidebar. |
| `components/bookmarks/library-table-view.tsx` | 592 | — | Extract column renderers and sort logic. |

### Open Issues from Previous Reviews

These items remain unresolved from prior code reviews:

| ID | Severity | Summary |
|---|---|---|
| CH-C18 | Medium | Folder parent resolution during pull is order-dependent (deferred — sync protocol) |
| CH-C21 | Medium | Web/iOS-created items without `ciderSyncId` skipped on desktop pull (deferred — sync protocol) |
| CH-D16 | Medium | List view and display modes inconsistent across card types |
| CH-D17 | Medium | Per-display panel position memory keyed only by resolution |

### Priority Recommendations

1. **No open High-severity items.** The 5 deferred/open medium issues are unchanged.
2. **Desktop large-file growth is accelerating.** 6 new files crossed 500 lines in one week. `BookmarksStorage.swift` at 2,601 lines (+183) is increasingly urgent. `SyncService.swift` and `SearchPaletteView.swift` both crossed 1,000 lines. `Constants.swift` nearly doubled (+407 lines) — likely from AI feature constants.
3. **AI feature area is the primary growth driver.** 3 of 6 new large files are AI-related (`AIAssistantTools`, `MLXToolExecutor`, `AIAssistantPanelView`), and ~6,800 of the 6,797 new Desktop LOC appears to correlate with AI assistant and kanban features. Establishing decomposition patterns early will prevent these from becoming the next `BookmarksStorage`.
4. **iOS `print()` statements** in `SyncClient.swift` should be converted to `os.Logger` to match Desktop conventions.
5. **iOS force unwraps** on `URL(string: bookmark.urlString)!` in `BookmarkReaderView.swift` are the highest-risk items — user-supplied URL strings can fail to parse.
6. **Web `console.log`** at `note-editor.tsx:533` is a debug leftover and should be removed.
7. **Web `syncInternal.ts`** grew +151 lines (+30%) in one week — approaching the complexity where push/pull extraction becomes worthwhile.

---

## Weekly Code Health Scan — 2026-03-29

### Summary

| Metric | Desktop | iOS | Web | Total |
|---|---|---|---|---|
| Source files | 243 (.swift) | 51 (.swift) | 86 (.ts/.tsx/.js) | 380 |
| Lines of code | 71,681 | 11,620 | 16,074 | 99,375 |
| TODO comments | 2 | 0 | 0 | 2 |
| FIXME comments | 0 | 0 | 0 | 0 |
| HACK comments | 0 | 0 | 0 | 0 |
| Files >500 lines | 39 | 5 | 7 | 51 |
| TypeScript errors | — | — | 0 | 0 |
| Swift build | N/A (no toolchain) | N/A | — | — |

### Trend vs. Prior Scan (2026-03-22)

| Metric | Prior | Current | Delta |
|---|---|---|---|
| Desktop files | 239 | 243 | +4 |
| Desktop LOC | 68,507 | 71,681 | +3,174 |
| Desktop >500L files | 38 | 39 | **+1** |
| iOS files | 51 | 51 | — |
| iOS LOC | 11,620 | 11,620 | — |
| iOS >500L files | 5 | 5 | — |
| Web files | 86 | 86 | — |
| Web LOC | 16,058 | 16,074 | +16 |
| Web >500L files | 7 | 7 | — |
| Total LOC | 96,185 | 99,375 | **+3,190** |
| Total >500L files | 50 | 51 | **+1** |

Growth rate has slowed significantly — +3,190 LOC (~3.3%) vs. +8,099 (~9.2%) last week. Growth is still entirely on Desktop (+3,174 LOC). iOS and Web are essentially unchanged.

### TODO/FIXME/HACK Comments

**Desktop — 2 TODO comments (new since last scan):**

Both are in `Services/VaultBookmarkService.swift`:

| Line | Comment | Severity |
|---|---|---|
| 220 | `// TODO: URL-based dedup can flip-flop when the same URL exists in different folders` | Low — known limitation, matches BookmarksStorage behavior |
| 305 | `// TODO: Cosmetic issue — the .webloc filename on disk still reflects the old title` | Low — UI reads from sidecar, not filename |

These are well-documented known-limitations, not forgotten work items. No action needed unless the features are revisited.

iOS and Web remain clean — zero TODO, FIXME, or HACK comments.

### TypeScript Health (Cider-Web)

`tsc --noEmit` passes with zero errors. The web codebase remains type-clean.

### Convention Violations

#### Desktop — Force Unwraps (4 instances, unchanged)

| File | Line | Code | Risk |
|---|---|---|---|
| `Views/Shared/MasonryLayout.swift` | 106 | `columnHeights.enumerated().min(...)!.offset` | Low — array guaranteed non-empty |
| `Services/SyncService.swift` | 961 | `URL(string: "\(siteURL)/api/sync/note-attachments-check")!` | Medium — interpolated URL could fail |
| `Services/SyncService.swift` | 1002 | `URL(string: "\(siteURL)/api/sync/upload-note-attachment")!` | Medium — same pattern |
| `Services/VaultFolderService.swift` | 533 | `index[folderID]!` | Low — safe after index write on line 518 |

#### iOS — Force Unwraps (9 instances, unchanged)

| File | Line | Code | Risk |
|---|---|---|---|
| `Views/BookmarkReaderView.swift` | 26, 28 | `URL(string: bookmark.urlString)!` | **High** — user-supplied URL string |
| `CiderApp.swift` | 109 | `UserDefaults(suiteName: "group.com.cider.app")!` | Medium — suite init can fail |
| `Shared/CiderTab.swift` | 69 | `UserDefaults(suiteName: "group.com.cider.app")!` | Medium — same pattern |
| `Views/SidebarView.swift` | 380 | `icon.unicodeScalars.first!.isASCII` | Low — guarded by prior check |
| `Views/TabChipBar.swift` | 90 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Views/FolderSheetView.swift` | 251 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Views/FolderBrowserView.swift` | 209 | `icon.unicodeScalars.first!.isASCII` | Low — same pattern |
| `Shared/MasonryLayout.swift` | 70 | `columnHeights.enumerated().min(...)!.offset` | Low — array guaranteed non-empty |

#### iOS — print() Statements (4 instances, unchanged)

All in `Shared/SyncClient.swift` — should use `os.Logger`:

| Line | Statement |
|---|---|
| 49 | `print("[Cider Raw Pull] ...")` |
| 51 | `print("  - \"...\": notes=\"...\"")` |
| 61 | `print("[Cider Pull] ...")` |
| 63 | `print("  - \"...\": notes=\"...\"")` |

#### Web — Console Statements (5 instances, unchanged)

| File | Line | Type | Verdict |
|---|---|---|---|
| `components/error-boundary.tsx` | 25 | `console.error` | Acceptable — error boundary |
| `components/providers/convex-provider.tsx` | 32 | `console.warn` | Acceptable — connection warning |
| `components/notes/note-editor.tsx` | 533 | `console.log` | **Remove** — debug log left in |
| `components/bookmarks/bookmark-capture.tsx` | 61 | `console.warn` | Acceptable — error handling |
| `convex/enrichment.ts` | 73 | `console.error` | Acceptable — server-side error |

#### Web — Type Safety Bypasses (29 `as any` / `as unknown`, down from 30)

14 in frontend components, 9 in convex backend, 6 in generated route tree. Patterns unchanged from last scan.

#### Desktop — Magic Number Spacing (1 instance)

| File | Line | Code |
|---|---|---|
| `Utilities/HighlightedText.swift` | 48 | `VStack(alignment: .leading, spacing: 10)` — should use `Spacing.md` (12) or `Spacing.sm` (8) |

### Large Files Needing Attention

**Desktop — 39 files >500 lines** (up from 38 — 1 newly crossed the threshold):

| File | Lines | Delta vs. Prior | Status |
|---|---|---|---|
| `Services/BookmarksStorage.swift` | 2,695 | +94 | **Critical.** Continued growth — decomposition overdue. |
| `Services/VaultBookmarkService.swift` | 2,113 | — | *New >500L entry since prior table.* Vault bookmark adoption/sync service — extract dedup, enrichment, and reconciliation logic. |
| `Views/Notes/InlineNoteEditorView.swift` | 1,390 | — | |
| `Services/NotesStorage.swift` | 1,331 | +26 | |
| `Views/Shared/FolderSidebarView.swift` | 1,321 | +2 | |
| `ViewModels/NotesViewModel.swift` | 1,248 | -10 | Slight reduction |
| `Services/AI/AIAssistantTools.swift` | 1,241 | — | |
| `Views/Shared/NewItemPopover.swift` | 1,136 | — | |
| `Views/SavedViews/SavedViewTabContent.swift` | 1,136 | -8 | |
| `Views/Shared/FolderDetailView.swift` | 1,091 | -158 | **Notable reduction** — good progress. |
| `Views/Bookmarks/BookmarkDetailsDraft.swift` | 1,073 | — | |
| `Services/SyncService.swift` | 1,063 | +8 | |
| `Views/Search/SearchPaletteView.swift` | 1,026 | +24 | |
| `Services/TrashStorage.swift` | 924 | +193 | **Major growth.** Investigate what was added. |
| `Utilities/Constants.swift` | 917 | +6 | Stabilized after last week's +407 spike. |
| `Services/VaultFolderService.swift` | 839 | +24 | |
| `Views/Shared/ClipboardViewerView.swift` | 829 | — | |
| `Services/AI/MLXToolExecutor.swift` | 768 | -6 | |
| `Views/Shared/TagDetailView.swift` | 747 | — | |
| `Views/Settings/SettingsComponents.swift` | 731 | +12 | |
| `Views/Home/HomeDashboardView.swift` | 725 | -173 | **Notable reduction** — good progress. |
| `Models/CiderConfig.swift` | 703 | +3 | |
| `Services/SearchService.swift` | 649 | +34 | |
| `Services/ActiveBrowserCaptureService.swift` | 649 | — | |
| `Views/Bookmarks/BookmarkThumbnailView.swift` | 616 | — | |
| `Services/BookmarkMetadataParser.swift` | 610 | +5 | |
| `App/AppDelegate.swift` | 601 | +2 | Already split into extensions (CH-D15). |
| `Views/Stacks/StackManagerSheet.swift` | 583 | — | |
| `Services/ContactStorage.swift` | 570 | +33 | |
| `Services/TodoCardStorage.swift` | 565 | +34 | |
| `Views/Settings/SettingsView+SubcategoryContent.swift` | 564 | — | |
| `Services/VaultStructureMigration.swift` | 561 | — | |
| `Views/Shared/DetailSlideOutView.swift` | 529 | -1 | |
| `Views/Notes/TipTapEditorView.swift` | 525 | — | |
| `Views/Kanban/KanbanBoardView.swift` | 520 | — | |
| `Views/Shared/ViewOptionsDropdown.swift` | 519 | — | |
| `Views/CiderPanelView+DetailViews.swift` | 517 | — | |
| `Views/AIAssistant/AIAssistantPanelView.swift` | 508 | — | |
| `Services/DateCardStorage.swift` | 503 | — | *New.* Just crossed 500 — iCal adoption and scan logic. |

**New file crossing 500 lines since last scan:** `DateCardStorage.swift` (503). The only new entrant this week, reflecting the slower growth rate.

**Positive trends:** `FolderDetailView.swift` dropped 158 lines and `HomeDashboardView.swift` dropped 173 lines — likely from view extraction refactoring. This is the kind of decomposition work needed across other large files.

**iOS — 5 files >500 lines (unchanged):**

| File | Lines | Suggested Action |
|---|---|---|
| `Views/BookmarkListView.swift` | 939 | Extract row builders and filter logic. |
| `Views/BookmarkDetailView.swift` | 725 | Extract metadata sections. |
| `Views/SidebarView.swift` | 614 | Extract navigation items and folder tree. |
| `Views/FolderBrowserView.swift` | 605 | Extract folder card components. |
| `Views/NoteEditorToolbar.swift` | 546 | Extract formatting button groups. |

**Web — 7 files >500 lines (unchanged count, minor changes):**

| File | Lines | Delta | Suggested Action |
|---|---|---|---|
| `components/bookmarks/bookmark-detail.tsx` | 1,080 | — | Extract metadata panel, action bar, and reader sub-components. |
| `components/landing/landing-page.tsx` | 844 | — | Extract individual landing sections. |
| `components/layout/sidebar.tsx` | 814 | — | Extract nav groups and folder tree. |
| `components/notes/note-editor.tsx` | 772 | — | Extract toolbar and formatting helpers. |
| `convex/syncInternal.ts` | 671 | +16 | Continued growth — push/pull extraction recommended. |
| `components/notes/note-detail.tsx` | 599 | — | Extract metadata sidebar. |
| `components/bookmarks/library-table-view.tsx` | 592 | — | Extract column renderers and sort logic. |

### Open Issues from Previous Reviews

These items remain unresolved from prior code reviews:

| ID | Severity | Summary |
|---|---|---|
| CH-C18 | Medium | Folder parent resolution during pull is order-dependent (deferred — sync protocol) |
| CH-C21 | Medium | Web/iOS-created items without `ciderSyncId` skipped on desktop pull (deferred — sync protocol) |
| CH-D16 | Medium | List view and display modes inconsistent across card types |
| CH-D17 | Medium | Per-display panel position memory keyed only by resolution |

### Priority Recommendations

1. **No open High-severity items.** The 5 deferred/open medium issues are unchanged.
2. **Desktop growth rate is decelerating** — +3,174 LOC this week vs. +6,797 last week. Only 1 new file crossed 500 lines (vs. 6 last week). The codebase is approaching 100K total LOC.
3. **Decomposition progress is visible.** `FolderDetailView` (-158) and `HomeDashboardView` (-173) both shrank meaningfully, showing active refactoring. More of this pattern should be applied to `BookmarksStorage` (2,695 lines, +94 this week) and `VaultBookmarkService` (2,113 lines).
4. **`TrashStorage.swift` grew +193 lines** (672→924) — the largest single-file growth this week. Worth reviewing what was added and whether it warrants extraction.
5. **iOS `print()` statements** in `SyncClient.swift` and **iOS force unwraps** on `URL(string: bookmark.urlString)!` remain the highest-priority convention violations — unchanged from last week.
6. **Web `console.log`** at `note-editor.tsx:533` is still a debug leftover and should be removed.
7. **2 new TODO comments** in `VaultBookmarkService.swift` — both are well-documented known-limitations (URL-based dedup flip-flop, stale .webloc filenames). Low severity, no immediate action needed.
