# Storage Integrity Loop

Automated audit for file-based storage layer correctness across the Cider vault system.

## When to run
- After any changes to VaultBookmarkService, NotesStorage, TrashStorage, VaultFolderService
- After adding new item types or storage paths
- Before releases
- Weekly health check

## How to run

Tell Claude: **"Run the storage integrity loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b storage-fixes`
2. Start the loop: `/loop 15m Run the storage integrity loop per Docs/QA/STORAGE_LOOP.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

## Rules checked

### 1. File ↔ Memory consistency
- Every in-memory mutation (folderID, URL, title, labels) must be persisted to disk (index, sidecar, or file)
- After `persist()` / `saveIndex()`, the next load from disk must produce identical state
- No property updates without corresponding file writes (the `updateURL` bug pattern)

### 2. Webloc file integrity
- `.webloc` plist must contain the same URL as the in-memory bookmark
- Moving a bookmark between folders must delete the source `.webloc` (no duplicates)
- Deleting a bookmark must remove the `.webloc` from disk
- Adoption scan must not re-adopt recently deleted URLs (TTL guard)

### 3. Sidecar consistency
- Every `.webloc` file with metadata must have a matching sidecar entry (keyed by filename)
- Renaming/moving a file must update the sidecar key in both source and destination
- Empty sidecars (no entries) must be cleaned up (deleted from disk)
- `persistSidecar` must use `BookmarkFileService.updateSidecar` — no manual encode/write

### 4. Trash round-trip integrity
- `trash()` → `restore()` must produce identical item state (URL, title, folderID, assets)
- Trash must use UUID-based paths (not name-based) to avoid collisions
- Restoring a bookmark must put assets in the correct per-folder directory
- `remove()` must not double-delete assets that `TrashStorage` already moved
- `recentlyDeletedURLs` must have TTL expiry (not grow forever)

### 5. Index/cache ↔ disk agreement
- `VaultBookmarkService` index cache must match what `BookmarkFileService.readAll()` produces
- `NotesStorage` index (`_cider_notes_index.json`) must have entries for all `.md` files on disk
- Orphaned index entries (file deleted from disk) must be cleaned up
- Orphaned files (not in index) must be adopted or flagged

### 6. Folder assignment integrity
- Bookmark/note `folderID` must match the vault folder where its file lives on disk
- Scan order must be consistent: vault folders first, then Inbox (both in load and adoption)
- Cross-folder duplicates (same URL in two folders) must be detected and cleaned up
- Moving an item to a folder must physically move the file AND update folderID + relativePath

### 7. Migration safety
- `VaultMigrationService` must use `uniqueFilename` to avoid collision on same-title bookmarks
- Migration must be idempotent — running twice must not duplicate or corrupt data
- Legacy `BookmarksStorage` references must not exist outside migration code

### 8. No stale references
- No consumer code should reference `BookmarksStorage.shared` (use `VaultBookmarkService.shared`)
- No hardcoded paths to `.cider/bookmarks/` — use `StoragePaths` helpers
- No assumptions about Inbox-only storage — items can live in any vault folder

## Files to scan

### Primary (storage layer)
- `Services/VaultBookmarkService.swift`
- `Services/BookmarkFileService.swift`
- `Services/VaultFolderService.swift`
- `Services/VaultMigrationService.swift`
- `Services/VaultStructureMigration.swift`
- `Services/NotesStorage.swift`
- `Services/TrashStorage.swift`
- `Services/ContactStorage.swift`
- `Services/DateCardStorage.swift`
- `Services/TodoCardStorage.swift`
- `Utilities/StoragePaths.swift`

### Consumers (correct delegation)
- `ViewModels/BookmarksViewModel.swift`
- `ViewModels/NotesViewModel.swift`
- `Views/CiderPanelView+Sidebar.swift`
- `Views/Shared/FolderSidebarView.swift`
- `Views/Shared/FolderDetailView.swift`
- `Views/Home/HomeDashboardView.swift`

## 3-pass verification

Each rule area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3.

## Known non-violations (skip these)
- `BookmarksStorage.shared` in `VaultMigrationService` — intentional legacy source for one-time migration
- `try?` on `FileManager.removeItem` in cleanup paths — harmless no-ops for missing files
- In-memory content cache misses (`contentCache`) — lazy loading, not data loss
- `relativePath` containing folder names with special characters — handled by URL encoding

## Live Vault Verification

In addition to static code analysis, each loop cycle should inspect the live vault at `~/CiderVault/` to catch drift between what the code thinks and what's actually on disk.

### 9. Vault filesystem health checks

Run these checks against the live vault directory:

**Orphan detection:**
- Find all `.webloc` files on disk → compare against `_cider_bookmarks.json` index → flag any not in index
- Find all index entries → check each has a corresponding `.webloc` file on disk → flag missing files
- Find all `.md` files in `Inbox/Notes/` and vault folders → compare against `_cider_notes_index.json` → flag orphans

**Duplicate detection:**
- Find `.webloc` files with the same URL in multiple folders (read the plist, extract URL)
- Find `.webloc` files in Inbox that also exist in a vault folder (same filename or same URL)
- Flag any duplicates found — these cause the "Reassigned N bookmarks" spam

**Sidecar health:**
- For each folder with `.webloc` files, check `_cider_sidecar.json` exists and has entries for each file
- Check for stale sidecar entries (filename in sidecar but no matching `.webloc` on disk)
- Check for empty sidecars (`{"items":{}}`) that should be deleted

**Trash health:**
- Check `.cider/bookmarks/.trash/` for items older than 30 days (should be auto-purged)
- Check `Inbox/Notes/.trash/` for the same
- Check `.cider/folders/.trash/` for UUID-named subdirectories (not name-based — name-based = old bug)
- Verify trash manifest entries match actual files in trash directories

**Folder structure:**
- For each vault folder, verify it exists on disk at the path `VaultFolderService` expects
- Check for folders on disk not tracked by `.cider/folders/index.json`
- Check for `index.json` entries pointing to non-existent directories

### 10. Cross-item consistency

**Bookmarks in folders:**
- For each bookmark with a `folderID`, verify the `.webloc` file is physically inside that folder's directory
- If the file is in a different directory, flag as folderID/path mismatch

**Notes in folders:**
- For each note with a `folderID`, verify the `.md` file is physically inside that folder's directory
- Check `relativePath` in the notes index matches the actual file location

**Item counts:**
- Compare bookmark count in index vs `.webloc` files on disk
- Compare note count in index vs `.md` files on disk (excluding index files)
- Large discrepancies indicate adoption or cleanup bugs

### Reporting format for live checks

For each check, report:
```
CHECK: [description]
STATUS: PASS | FAIL | WARN
DETAILS: [specifics if not PASS]
```

Warnings are for non-critical drift (e.g., empty sidecar file). Failures are for data integrity issues (orphaned files, missing files, duplicates).

## Integration Tests (Exercise the Storage)

These tests actually create, move, and delete items to verify the full round-trip works. All operations use a dedicated test folder (`_StorageAuditTest`) that is created at the start and cleaned up at the end. **No real user data is touched.**

### Setup & teardown
- Create vault folder `_StorageAuditTest` via `VaultFolderService` at start
- Delete it (and all contents) at the end
- If the folder already exists from a previous failed run, delete it first

### Test 1: Bookmark create → verify on disk
1. Create a `.webloc` file in `~/CiderVault/_StorageAuditTest/` with a test URL (e.g., `https://example.com/storage-audit-test`)
2. Wait for adoption scan (or trigger manually)
3. Verify: `.webloc` exists on disk, sidecar has an entry, index has the bookmark
4. **PASS** if all three agree. **FAIL** if any missing.

### Test 2: Bookmark move → verify file moved
1. Using the bookmark from Test 1, move it to `Inbox/Bookmarks/` (set folderID to nil)
2. Verify: `.webloc` is now in `Inbox/Bookmarks/`, NOT in `_StorageAuditTest/`
3. Verify: sidecar entry removed from source, added to destination
4. Verify: bookmark's `relativePath` and `folderID` updated in index
5. **PASS** if old location clean and new location correct. **FAIL** if duplicate or stale.

### Test 3: Bookmark move back → verify no duplicates
1. Move the bookmark back to `_StorageAuditTest/`
2. Verify: `.webloc` only exists in `_StorageAuditTest/`, not in Inbox
3. Verify: no "Reassigned" log spam on next adoption scan
4. **PASS** if single copy in correct location. **FAIL** if duplicates.

### Test 4: Bookmark delete → verify trash
1. Delete the bookmark via `VaultBookmarkService.remove()`
2. Verify: `.webloc` removed from `_StorageAuditTest/`
3. Verify: trash manifest has the bookmark entry
4. Verify: bookmark no longer in index or `bookmarks` array
5. Verify: adoption scan does NOT re-adopt the URL (TTL guard)
6. **PASS** if cleanly trashed. **FAIL** if orphaned or zombie re-adopted.

### Test 5: Bookmark restore → verify round-trip
1. Restore the trashed bookmark
2. Verify: `.webloc` reappears on disk at correct location
3. Verify: bookmark back in index with correct folderID, title, URL
4. Verify: sidecar entry restored
5. **PASS** if state matches pre-delete. **FAIL** if data lost.

### Test 6: Note create → verify on disk
1. Create a note via `NotesStorage.shared.createNew(initialContent: "Storage audit test")`
2. Verify: `.md` file exists in `Inbox/Notes/`
3. Verify: notes index has entry with correct filename
4. **PASS** if file and index agree. **FAIL** if missing.

### Test 7: Note move to folder → verify file moved
1. Move the note to `_StorageAuditTest/` via `NotesStorage.shared.assignNote()`
2. Verify: `.md` file is in `~/CiderVault/_StorageAuditTest/`, NOT in `Inbox/Notes/`
3. Verify: note's `folderID` and `relativePath` updated in index
4. **PASS** if single copy in correct location. **FAIL** if duplicate or stale.

### Test 8: Note delete → verify trash
1. Delete the note
2. Verify: `.md` removed from `_StorageAuditTest/`
3. Verify: trash manifest has the note entry
4. **PASS** if cleanly trashed. **FAIL** if orphaned.

### Test 9: Note restore → verify round-trip
1. Restore the trashed note
2. Verify: `.md` reappears at correct location with correct content
3. Verify: note back in index with correct folderID
4. **PASS** if content and metadata match pre-delete. **FAIL** if data lost.

### Test 10: URL update → verify webloc rewrite
1. Create a new test bookmark in `_StorageAuditTest/`
2. Update its URL via `VaultBookmarkService.shared.updateURL()`
3. Read the `.webloc` plist directly from disk
4. Verify: plist contains the NEW URL, not the old one
5. **PASS** if plist matches in-memory URL. **FAIL** if stale.

### Test 11: Duplicate URL detection
1. Create a `.webloc` file manually in `Inbox/Bookmarks/` with the same URL as the Test 10 bookmark
2. Trigger adoption scan
3. Verify: the duplicate is detected and cleaned up (Inbox copy deleted)
4. Verify: bookmark remains in `_StorageAuditTest/` with correct folderID
5. **PASS** if single copy survives. **FAIL** if both kept or wrong one deleted.

### Cleanup
- Delete all test bookmarks and notes created during the run
- Delete the `_StorageAuditTest` folder via `VaultFolderService`
- Verify: no leftover files, index entries, or sidecar entries from the test

### Reporting format
```
TEST 1: Bookmark create → verify on disk ........... PASS
TEST 2: Bookmark move → verify file moved .......... PASS
TEST 3: Bookmark move back → verify no duplicates .. PASS
TEST 4: Bookmark delete → verify trash ............. PASS
TEST 5: Bookmark restore → verify round-trip ....... PASS
TEST 6: Note create → verify on disk ............... PASS
TEST 7: Note move to folder → verify file moved .... PASS
TEST 8: Note delete → verify trash ................. PASS
TEST 9: Note restore → verify round-trip ........... PASS
TEST 10: URL update → verify webloc rewrite ........ PASS
TEST 11: Duplicate URL detection ................... PASS
CLEANUP: Test folder removed ....................... PASS
```

Any FAIL stops the run and reports the mismatch details. The test folder is always cleaned up, even on failure.

## Progress tracking

Results are logged in `Docs/QA/STORAGE_AUDIT.md` with a progress tracker table and detailed fix log. Create this file on first run.
