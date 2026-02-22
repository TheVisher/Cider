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

---

## Correctness / Data

### ~~CH-C01 — Storage path split on directory change~~ ✅ Fixed 2026-02-21

`fileURL` in ContactStorage, ProjectStorage, DateCardStorage, CardStackStorage, CardLabelStorage, SavedViewStorage, and ExternalSourceStorage changed from stored properties (set at `init()`) to computed properties that call `StoragePaths.ciderDataDirectoryURL()` at runtime. Each storage gained a public `reload()` method. `AppDelegate.handleConfigChanged()` calls `reload()` on all 6 after updating the BookmarksStorage directory. Also: `CiderConfig.bookmarksDirectory` renamed to `ciderDataDirectory`; CodingKeys alias keeps JSON key `"bookmarksDirectory"` for backward compat.

### ~~CH-C02 — Note restore orphan risk in TrashStorage~~ ✅ Fixed 2026-02-21

Move is now `try fm.moveItem` inside a `do/catch`; on failure, function returns early leaving the manifest intact. `restoreFromTrash` and `removeFromManifest` only called on success. If the trash file is already gone (manual deletion), manifest is cleaned but index is not updated.

### ~~CH-C03 — Note search false negatives from 120-char cap~~ ✅ Fixed 2026-02-21

`notePreview` renamed `noteStrippedContent` and returns the full stripped string. `searchNotes` matches against the full content; `prefix(120)` applied only to the `subtitle` field in the returned `SearchResult`.

### CH-C04 — Select All skips date cards and contacts on Home tab (High)

`selectAll()` in `CiderPanelView` iterates `bookmarksViewModel.bookmarks` and `notesViewModel.notes` only. Date cards and contacts visible in the Home feed are not selected.

> **Note:** Only address once bulk-delete/move actions support all entity types. Until then, `// TODO: CH-C04` comment added at the call site so it's findable.

- [ ]

- [ ]

- File refs: `Sources/Cider/Views/CiderPanelView.swift` — TODO comment added at `.home` case in `selectAllVisibleItems()`

- First reported: 2026-02-20

- [ ] Fixed (partial — TODO marker added; full fix deferred until bulk actions support all entity types)

---

## Performance

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

---

## Design & Architecture

### ~~CH-D01 — Carbon fallback hotkeys consume keys when disabled~~ ✅ Fixed 2026-02-21

`handleHotKeyEvent` in both `NotesHotkeyDetector` and `BookmarksHotkeyDetector` now returns `OSStatus(eventNotHandledErr)` (not `noErr`) when `isEnabled` is false, so the event passes through to other handlers.

### ~~CH-D02 — Undo-toast hover resets timer instead of pausing~~ ✅ Fixed 2026-02-21

Hover-enter branch now only stops the timer and sets `undoToastIsHovering = true`; `undoToastRemaining` and `undoToastModel.progress` are no longer reset. Hover-exit resumes the timer from where it left off.

### ~~CH-D03 — Non-spring animation curves in panel transitions~~ ✅ Fixed 2026-02-21

Replaced `CAMediaTimingFunction(name: .easeInEaseOut)` with `CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)` (fast-out deceleration curve, perceptually matching a critically-damped spring) in all three panel files. Reduce-motion guard was already present.

### ~~CH-D04 — Search palette uses `.shadow()` instead of shape-based shadow~~ ✅ Fixed 2026-02-21

Replaced `.shadow(...)` with `.background { RoundedRectangle.fill(.black).blur(24).offset(y:12).opacity(shadowShapeFullOpacity) }` — same pattern as `AcrylicPanelBackground`.

### ~~CH-D05 — Some UI elements ignore global text-size preference~~ ✅ Fixed 2026-02-21

Added `CiderFont.scale: CGFloat` public property. Changed `emptyStateIcon` from `static let` to `static var` using `scaled(36)`. Fixed traffic light symbol fonts in `CiderPanelShell.swift` to multiply by `CiderFont.scale`. `appIcon` left as fixed 64pt (purely decorative on About screen). (Note: NotesPanelView and BookmarksPanelView references removed — standalone panels deleted in Feb 2026 consolidation.)

---

## Dead Code & Cleanup

### ~~CH-L01 — Stale feature flags with no runtime gating~~ ✅ Fixed 2026-02-21

`enableDateCards`, `enableStacks`, `enableCalendarProjection` removed from `CiderConfig` (CodingKeys, var declarations, `default`, memberwise `init`, `init(from:)`). `enableSavedViewTabs` and `enableLinkedSources` kept — both actively gate behavior in `CiderPanelView` and `FolderSidebarView`.

### ~~CH-L02 — Dead code artifacts~~ ✅ Fixed 2026-02-21

`SystemStatus.swift` and `FeatureSettings.swift` deleted (confirmed zero references). `ProjectTabContent.swift:16` reported as unused import was a false positive — only `import SwiftUI` exists at line 1 and is used; no change needed.

---

## Resolved

### ✅ HI-02 — Test suite failed to compile (TileNode / SplitOrientation)

Stale tests from the window-manager era referenced removed types. Resolved when the window management pivot cleaned out these modules.

- Fixed: 2026-02

### ✅ LO-01 — SQLite doc drift

Docs previously described SQLite metadata storage; implementation is file/JSON-based. Documentation updated to reflect actual architecture.

- Fixed: 2026-02