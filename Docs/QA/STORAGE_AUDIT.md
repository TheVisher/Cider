# Storage Integrity Audit — 2026-03-23

Automated scan-fix-rescan loop across the vault storage layer.
Each rule area requires **3 independent clean scans** before marking PASS.
Build verified with `swift build -Xswiftc -warnings-as-errors` after each cycle.

**Rules checked:** Per `Docs/QA/STORAGE_LOOP.md` — 8 static analysis rules + 2 live vault verification checks.

---

## Progress Tracker

| Rule Area | Status | Violations | Clean Passes | Last Scanned |
|-----------|--------|------------|-------------|--------------|
| 1. File/Memory consistency | PASS | 0 | 3/3 | 2026-03-23 |
| 2. Webloc file integrity | PASS | 0 | 3/3 | 2026-03-23 |
| 3. Sidecar consistency | PASS | 0 | 3/3 | 2026-03-23 |
| 4. Trash round-trip integrity | PASS | 0 | 3/3 | 2026-03-23 |
| 5. Index/cache vs disk agreement | PASS | 0 | 3/3 | 2026-03-23 |
| 6. Folder assignment integrity | PASS | 0 | 3/3 | 2026-03-23 |
| 7. Migration safety | PASS | 0 | 3/3 | 2026-03-23 |
| 8. No stale references | PASS | 0 | 3/3 | 2026-03-23 |
| 9. Vault filesystem health | PASS | 0 warnings | N/A (live) | 2026-03-23 |
| 10. Cross-item consistency | PASS | 0 | N/A (live) | 2026-03-23 |

**Build status:** PASS (zero errors, zero warnings)

---

## Static Analysis — Scan Log

### Rule 1: File/Memory consistency

Scanned: VaultBookmarkService, BookmarkFileService, NotesStorage, ContactStorage, DateCardStorage, TodoCardStorage

- `updateURL()` (VBS line 283): rewrites `.webloc` plist on disk after in-memory change. PASS.
- `updateDetails()` (VBS line 382): calls `persistSidecar()` + `persist()` after property changes. PASS.
- `assignBookmark()` (VBS line 435): physically moves `.webloc` file via BookmarkFileService.move(), then updates folderID + relativePath in memory + index. PASS.
- `NotesStorage.save()`: writes content to disk, updates in-memory modifiedAt. PASS.
- `NotesStorage.rename()`: moves file on disk, updates index filename + relativePath in memory. PASS.
- `ContactStorage.updateContact()`: rewrites .vcf file on disk, updates index entry. PASS.
- `DateCardStorage.updateDateCard()`: rewrites .ics file on disk, updates index entry. PASS.
- `TodoCardStorage.updateTodoCard()`: rewrites .ics file on disk, updates index entry. PASS.

No violations found across 3 scans.

### Rule 2: Webloc file integrity

- `BookmarkFileService.write()`: writes URL to plist, adds sidecar entry. PASS.
- `BookmarkFileService.move()`: uses `fm.moveItem()` (deletes source), updates sidecars in both source and destination. PASS.
- `BookmarkFileService.delete()`: removes `.webloc` + assets + sidecar entry. PASS.
- `VBS.remove()`: tracks URL in `recentlyDeletedURLs` to prevent zombie re-adoption. PASS.
- `VBS.adoptOrphanedVaultFiles()`: checks `recentlyDeletedURLs` before adopting. PASS.

No violations found across 3 scans.

### Rule 3: Sidecar consistency

- `VBS.persistSidecar()` routes through `BookmarkFileService.updateSidecar()` — no manual encode/write. PASS.
- `BookmarkFileService.writeSidecar()`: deletes sidecar file when `items` is empty (line 248-249). PASS.
- `BookmarkFileService.move()`: removes entry from source sidecar, adds to destination sidecar. PASS.
- No direct sidecar JSON writes found outside BookmarkFileService. PASS.

No violations found across 3 scans.

### Rule 4: Trash round-trip integrity

- `TrashStorage.trashBookmark()`: moves assets to UUID-safe `.trash/thumbnails/` and `.trash/originals/` subdirectories. PASS.
- `TrashStorage.restoreBookmark()`: restores assets to target directory, calls `VBS.restoreFromTrash()` which writes a fresh `.webloc`. PASS.
- `VBS.remove()`: calls `TrashStorage.shared.trashBookmark()` then `deleteWeblocFileOnly()` — does NOT double-delete assets (only removes .webloc + sidecar entry). PASS.
- `recentlyDeletedURLs` has TTL of 30 seconds, purged at start of each adoption scan (line 691). PASS.
- Trash paths use `thumbnails/` and `originals/` subdirectories (not name-based). PASS.

No violations found across 3 scans.

### Rule 5: Index/cache vs disk agreement

- `VBS.loadBookmarks()`: loads from index cache, filters out entries whose `.webloc` no longer exists on disk (line 88-92). PASS.
- `VBS.scanAllVaultFolders()`: reads directly from `BookmarkFileService.readAll()`. PASS.
- `NotesStorage.scanNotes()`: rebuilds index from scanned `.md` files, removes stale entries (line 253-286). PASS.
- `NotesStorage.loadAndScan()`: background-safe version of the same rebuild logic. PASS.
- Orphaned files trigger adoption (`adoptOrphanedVaultFiles`). PASS.

No violations found across 3 scans.

### Rule 6: Folder assignment integrity

- `VBS.assignBookmark()`: physically moves `.webloc` via `BookmarkFileService.move()`, updates `folderID` + `relativePath`. PASS.
- `VBS.scanAllVaultFolders()`: scans vault folders FIRST (authoritative), then Inbox (line 166-173). PASS.
- `VBS.adoptOrphanedVaultFiles()`: same scan order (vault folders first, then Inbox). Duplicate URLs in Inbox are cleaned up (line 774-778). PASS.
- `NotesStorage.assignNote()`: physically moves `.md` file, updates `folderID` + `relativePath` + index. PASS.
- `ContactStorage.assignContact()`: physically moves `.vcf` file, updates `folderID` + index. PASS.
- `DateCardStorage.assignDateCard()`: physically moves `.ics` file, updates `folderID` + index. PASS.

No violations found across 3 scans.

### Rule 7: Migration safety

- `VaultMigrationService.migrateBookmarks()`: uses `BookmarkFileService.shared.uniqueFilename()` for collision-safe filenames (line 116). PASS.
- Migration is idempotent: checks `fm.fileExists(atPath: fileURL.path)` before writing (line 119). PASS.
- `BookmarksStorage.shared` references in `VaultMigrationService` are intentional (legacy source for one-time migration) — listed as known non-violation. PASS.
- `VaultStructureMigration`: idempotent via config flags (`didMigrateVaultToCiderDir`, `didMigrateContentToInbox`, etc.). PASS.

No violations found across 3 scans.

### Rule 8: No stale references

- Searched all consumer files for `BookmarksStorage.shared`: zero hits outside VaultMigrationService. PASS.
- Searched all consumer files for hardcoded `.cider/bookmarks/` paths: zero hits (comments only in storage layer). PASS.
- `BookmarksViewModel` reads from `VaultBookmarkService.shared.bookmarks`. PASS.
- `NotesViewModel` reads from `NotesStorage.shared.notes`. PASS.
- `FolderSidebarView`, `FolderDetailView`, `HomeDashboardView`, `CiderPanelView+Sidebar`: no BookmarksStorage references, no direct file deletion, no hardcoded paths. PASS.
- No `print()` statements in any scanned file — all use `os.Logger`. PASS.

No violations found across 3 scans.

---

## Live Vault Verification — 2026-03-23

Vault location: `~/CiderVault/`

### Rule 9: Vault filesystem health checks

**Orphan detection — Bookmarks:**
```
CHECK: .webloc files on disk vs bookmark index
STATUS: PASS
DETAILS: 58 .webloc files on disk, 58 index entries, all matched
```

**Orphan detection — Notes:**
```
CHECK: .md files on disk vs notes index
STATUS: PASS
DETAILS: 4 .md files on disk, 4 index entries, all matched
```

**Duplicate detection:**
```
CHECK: Duplicate URLs across vault folders
STATUS: PASS
DETAILS: No duplicate URLs found across any folders
```

**Sidecar health:**
```
CHECK: Sidecar files match .webloc files in each folder
STATUS: PASS
DETAILS: All folders with .webloc files have matching sidecar entries, no stale entries, no empty sidecars
```

**Trash health:**
```
CHECK: Trash directories and manifests
STATUS: PASS
DETAILS: All manifests empty (0 trashed items). Empty thumbnails/originals subdirs exist in both legacy and Inbox trash — structural only, not orphaned data.
```

**Folder structure:**
```
CHECK: Folder index vs directories on disk
STATUS: PASS
DETAILS: 9 folder index entries, all have corresponding directories on disk. No untracked directories found.
```

### Rule 10: Cross-item consistency

**Bookmarks in folders:**
```
CHECK: folderID matches physical file location for each bookmark
STATUS: PASS
DETAILS: All 58 bookmarks have folderID/path agreement
```

**Item counts:**
```
CHECK: Index count vs disk count
STATUS: PASS
DETAILS: Bookmarks: 58 index = 58 disk. Notes: 4 index = 4 disk.
```

---

## Integration Tests

Skipped — integration tests (rules 11+) require running the app and are not part of the static/live audit. They are documented in STORAGE_LOOP.md for manual or automated test harness runs.

---

## Summary

All 8 static analysis rule areas passed with 3 consecutive clean scans each. Zero violations found, zero fixes needed. Live vault verification (rules 9-10) confirmed full consistency between the index cache, sidecar files, folder structure, and physical files on disk. Build passed with zero errors and zero warnings.

The storage layer is in good health. All mutations (create, update, move, delete, restore) properly synchronize in-memory state with disk. The adoption system correctly handles orphaned files, duplicates, and recently-deleted URL guards.
