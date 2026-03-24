# Bookmark Storage System Audit

**Date:** 2026-03-23
**Purpose:** Blueprint for replacing BookmarksStorage with file-based VaultBookmarkService

## The Problem

BookmarksStorage reads from monolithic `_cider_bookmarks_metadata.json` + `bookmarks.html`. Since the file migration, it dual-writes to `.webloc` files but never reads them as primary source. When agents/Finder move files, the JSON doesn't know.

## Current Load Path

1. Read `_cider_bookmarks_metadata.json` (all metadata)
2. Read `bookmarks.html` (URL list, dates)
3. Merge: HTML provides URLs, JSON provides metadata
4. Run `adoptOrphanedVaultFiles()` as band-aid for .webloc files

## Current Write Path (persist)

1. Write `bookmarks.html`
2. Write `_cider_bookmarks_metadata.json`
3. Push to SyncService
4. Write `.webloc` files + per-folder `_cider_bookmarks.json` sidecars (dual-write)

## Known Bugs

1. **`.webloc` not moved on folder reassign** — `assignBookmark()` updates folderID in memory but doesn't call `BookmarkFileService.move()`. File stays in old location.
2. **URL-based dedup in adoption** — duplicate bookmarks with same URL but different metadata silently lost
3. **Folder ID mismatch** — legacy `Folder` UUIDs vs `VaultFolder` UUIDs, bridged by `reconcileJSONFoldersWithVaultFolders()`
4. **Thumbnail paths hardcoded** — resolve against `.cider/bookmarks/`, not per-folder
5. **Carousel images not trashed** — left as orphans when bookmark deleted
6. **VaultMigrationService reads legacy folders** — tied to old system

## Files the Current System Reads

| File | Path | When |
|------|------|------|
| `_cider_bookmarks_metadata.json` | `.cider/bookmarks/` | On load (primary) |
| `bookmarks.html` | `.cider/bookmarks/` | On load (URL source) |
| `.webloc` files | vault folders | Only during `adoptOrphanedVaultFiles()` |
| `_cider_bookmarks.json` sidecars | per-folder | Only during adoption |

## Files the Current System Writes

| File | Path | When |
|------|------|------|
| `_cider_bookmarks_metadata.json` | `.cider/bookmarks/` | Every persist() |
| `bookmarks.html` | `.cider/bookmarks/` | Every persist() |
| `.webloc` plist files | vault folders | Every persist() (dual-write) |
| `_cider_bookmarks.json` sidecars | per-folder | Every persist() |
| `.thumbnails/<UUID>.png` | `.cider/bookmarks/.thumbnails/` | Enrichment |
| `.originals/<UUID>.<ext>` | `.cider/bookmarks/.originals/` | Enrichment |

## Public API to Replicate

### CRUD
- `add(urlString:title:) -> Bookmark?`
- `addImageBookmark(title:) -> Bookmark`
- `addFromPasteboard() -> Bookmark?`
- `remove(_ bookmark:) -> TrashItem`
- `removeAll(_ bookmarks:) -> [TrashItem]`
- `restoreFromTrash(_ bookmark:)`
- `updateDetails(for:title:notes:tags:labelIDs:urlString:) -> Bool`
- `updateURL(for:urlString:)`
- `assignBookmark(_:toFolder:) -> Bool` — **MUST move .webloc file**

### Labels
- `assignLabel(_:labelID:) -> Bool`
- `removeLabel(_:labelID:) -> Bool`
- `removeLabelsFromAll(labelID:)`

### Thumbnails/Media
- `assignThumbnail(for:fromDroppedString:) async -> Bool`
- `assignThumbnail(for:fromLocalFileURL:) -> Bool`
- `assignThumbnail(for:imageData:preferredFileExtension:) -> Bool`
- `setReaderUnavailable(_:for:)`
- `setPreferredHeroMode(_:for:)`
- `setMediaType(_:for:)`
- `applyAIResults(...)`
- `refetchMetadata(for:)`

### Sync
- `addFromSync(...)`
- `updateFromSync(...)`
- `removeSynced(_:)`
- `trashFromSync(_:)`

### Folders (delegate to VaultFolderService — no legacy)
- No more `createFolder`, `renameFolder`, `deleteFolder` — use VaultFolderService

### Import/Export
- `importNetscapeHTML(from:) -> Int`
- `exportNetscapeHTML(to:)`

### Other
- `reloadFromDisk()`
- `updateDirectory(to:)`
- `adoptOrphanedVaultFiles()`
- `previewNormalizedURLString(from:) -> String?`

## Consumers (files referencing BookmarksStorage.shared)

~30 files, ~63 call sites. Key ones:
- BookmarksViewModel.swift — main UI wrapper
- SyncService.swift — push/pull
- TrashStorage.swift — trash/restore
- AppDelegate.swift + AppDelegate+Toasts.swift — capture flows
- SpotlightIndexer.swift — search index
- CardLabelStorage.swift — label operations
- CiderUndoManager.swift — undo
- VaultIndexService.swift — vault index
- BookmarkAIEnrichment.swift — AI summaries
- MLXToolExecutor.swift — local AI tool calls
- Multiple view files for display/actions

## What VaultBookmarkService Must Do

1. **Load from files** — scan vault folders for .webloc + read sidecars
2. **Performance cache** — write `_cider_bookmarks_index.json` for fast startup
3. **Move files on folder assign** — call `BookmarkFileService.move()`
4. **No legacy folders** — use VaultFolderService exclusively
5. **No monolithic JSON** — stop reading/writing `_cider_bookmarks_metadata.json` and `bookmarks.html`
6. **Per-folder thumbnails** — store in folder's `.thumbnails/` dir
7. **Proper trash** — move .webloc + all assets including carousel images
8. **Same public API** — consumers just swap `BookmarksStorage.shared` → `VaultBookmarkService.shared`
9. **FSEvents adoption** — debounced scan for externally added/moved files
10. **Update vault CLAUDE.md** — tell agents to work with files, not JSON
