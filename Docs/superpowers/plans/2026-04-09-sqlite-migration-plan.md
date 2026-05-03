# SQLite Migration Implementation Plan

> Status: historical completed implementation plan. Board `p1l2m3`, card `plan002`, records this work as completed on `2026-04-11`. For current storage architecture, use `Docs/Architecture/STORAGE_DOCTRINE.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Cider's JSON-based metadata persistence with a unified SQLite database, enabling relational queries, atomic writes, and concurrent access while keeping files as the source of truth.

**Architecture:** Approach A -- keep in-memory @Published arrays, swap SQLite persistence underneath. Unified items table with per-type detail tables. Startup reconciliation syncs DB against filesystem. Services load from DB on init, write to DB on mutation.

**Tech Stack:** Swift 6.2, macOS 26+, SQLite3 (system framework -- no third-party dependency), Swift Testing

**Spec:** Docs/superpowers/specs/2026-04-09-sqlite-migration-design.md

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| Sources/Cider/Database/CiderDatabase.swift | Connection management, singleton, WAL mode, foreign keys |
| Sources/Cider/Database/CiderSchema.swift | All CREATE TABLE / CREATE INDEX statements, schema version tracking |
| Sources/Cider/Database/DatabaseMigrations.swift | Version-based migration runner (v0 to v1 creates all tables) |
| Sources/Cider/Database/DatabaseHelpers.swift | Row encoding/decoding helpers (UUID to TEXT, Date to REAL, Array to JSON TEXT) |
| Sources/Cider/Database/SQLStatement.swift | Lightweight prepared statement wrapper (bind, step, column accessors) |
| Sources/Cider/Database/VaultReconciler.swift | Startup filesystem-to-DB reconciliation |
| Tests/CiderTests/CiderDatabaseTests.swift | Database bootstrap, schema creation, helper tests |
| Tests/CiderTests/LabelDatabaseTests.swift | Labels CRUD via SQLite |

### Modified Files (per migration phase)

| Phase | Files Modified |
|-------|---------------|
| Labels | Sources/Cider/Services/CardLabelStorage.swift |
| Folders | Sources/Cider/Services/VaultFolderService.swift |
| Bookmarks | Sources/Cider/Services/VaultBookmarkService.swift, Sources/Cider/Services/BookmarkFileService.swift |

Later phases follow the same pattern per service. Each phase modifies one storage service to read/write SQLite instead of JSON.

---

## Task 1: Database Bootstrap -- Connection and Schema

**Files:**
- Create: Sources/Cider/Database/CiderDatabase.swift
- Create: Sources/Cider/Database/CiderSchema.swift
- Create: Sources/Cider/Database/DatabaseMigrations.swift
- Create: Sources/Cider/Database/DatabaseHelpers.swift
- Create: Sources/Cider/Database/SQLStatement.swift
- Test: Tests/CiderTests/CiderDatabaseTests.swift

This task builds the shared database layer that all storage services will use.

- [ ] **Step 1: Create the Sources/Cider/Database/ directory**

- [ ] **Step 2: Write SQLStatement.swift -- lightweight prepared statement wrapper**

Thin wrapper around sqlite3_stmt providing type-safe bind and column access methods. Handles bind for String?, Int64, Double, Int. Column accessors for string, double, int, int64, bool -- both nullable and non-nil variants. Finalizes statement in deinit.

- [ ] **Step 3: Write DatabaseHelpers.swift -- type conversion helpers**

Static helper enum with round-trip conversions:
- UUID to/from TEXT (uuidString)
- Date to/from REAL (timeIntervalSinceReferenceDate)
- [String] to/from JSON TEXT
- [UUID] to/from JSON TEXT
- Codable to/from JSON TEXT

- [ ] **Step 4: Write CiderDatabase.swift -- connection management**

MainActor-isolated singleton. Methods: open(at: URL), close(), exec(String), prepare(String) -> SQLStatement, withTransaction(() throws -> T). On open: enables WAL mode, enables foreign keys, runs DatabaseMigrations.run(). Error type: CiderDatabaseError with cases for open, prepare, step, exec.

- [ ] **Step 5: Write CiderSchema.swift -- table definitions**

Static string constants for every CREATE TABLE and CREATE INDEX statement from the spec. Property allTables returns them in dependency order (folders before items, items before detail tables). All use IF NOT EXISTS.

- [ ] **Step 6: Write DatabaseMigrations.swift -- version-based migration runner**

Creates schema_version table. Reads current version. If < 1, runs migrateToV1 which creates all tables and indexes inside a transaction, then sets version to 1. Future migrations slot in as if currentVersion < 2 blocks.

- [ ] **Step 7: Write tests for database bootstrap**

Tests in CiderDatabaseTests.swift using Swift Testing (@Suite, @Test, #expect):
- Opens database and creates schema (verify schema_version = 1, items table exists, foreign keys enabled)
- Reopening existing database preserves data (insert label, close, reopen, verify label exists)
- Transaction rolls back on error (insert inside transaction, force duplicate key error, verify rollback)
- DatabaseHelpers round-trips correctly (UUID, Date, String arrays, UUID arrays, nil handling)

Each test creates a temp directory, opens a fresh CiderDatabase, cleans up in defer.

- [ ] **Step 8: Run tests to verify they pass**

Run: swift test --filter CiderDatabaseTests
Expected: All 4 tests pass

- [ ] **Step 9: Commit**

Message: feat(db): add SQLite database layer with schema, migrations, and helpers

---

## Task 2: Labels Migration

**Files:**
- Modify: Sources/Cider/Services/CardLabelStorage.swift
- Test: Tests/CiderTests/LabelDatabaseTests.swift

Migrate the simplest storage service first to validate the SQLite layer works end-to-end.

- [ ] **Step 1: Write test -- labels round-trip through SQLite**

Test in LabelDatabaseTests.swift: create a CardLabel, insert it into the labels table using prepared statements and DatabaseHelpers, read it back, verify name and color match.

- [ ] **Step 2: Run test to verify it passes**

Run: swift test --filter LabelDatabaseTests
Expected: PASS

- [ ] **Step 3: Add SQLite persistence methods to CardLabelStorage**

Three new methods:
- loadFromDatabase(_ db: CiderDatabase) -- SELECT all labels ordered by name, build CardLabel array, assign to self.labels
- persistToDatabase(_ db: CiderDatabase, label: CardLabel) -- INSERT OR REPLACE into labels table
- deleteFromDatabase(_ db: CiderDatabase, labelID: UUID) -- DELETE from labels WHERE id = ?

- [ ] **Step 4: Run all tests**

Run: swift test --filter "LabelDatabaseTests|CiderDatabaseTests"
Expected: All pass

- [ ] **Step 5: Commit**

Message: feat(db): add SQLite read/write methods to CardLabelStorage

- [ ] **Step 6: Switch CardLabelStorage to use SQLite as primary persistence**

Replace JSON load() call in init() with loadFromDatabase(). Replace persist() calls in mutation methods with persistToDatabase(). Also write labels-backup.json on every mutation for rebuild recoverability.

- [ ] **Step 7: Verify parity**

Parity checklist:
- Same label count before and after migration
- Same label IDs
- Same names and colors
- Labels appear correctly in sidebar
- Creating/deleting/renaming labels persists across app restart

- [ ] **Step 8: Commit**

Message: feat(db): migrate CardLabelStorage to SQLite persistence

---

## Task 3: Folders Migration

**Files:**
- Modify: Sources/Cider/Services/VaultFolderService.swift

Same pattern as labels. Folders must be migrated before bookmarks/notes/etc. because items.folder_id references folders.id.

- [ ] **Step 1: Add SQLite persistence methods to VaultFolderService**

Same pattern as labels: loadFromDatabase(), persistToDatabase(), deleteFromDatabase(). Read/write from folders table including id, relative_path, created_at, updated_at, icon, cover_image_path, cover_image_offset_y.

- [ ] **Step 2: Switch VaultFolderService to use SQLite as primary persistence**

Replace JSON load/persist with SQLite equivalents. Keep in-memory folders array unchanged.

- [ ] **Step 3: Verify parity**

- Same folder count
- Same folder IDs and paths
- Folders appear in sidebar
- Creating/moving folders persists across restart

- [ ] **Step 4: Commit**

Message: feat(db): migrate VaultFolderService to SQLite persistence

---

## Task 4: Bookmarks Migration

**Files:**
- Modify: Sources/Cider/Services/VaultBookmarkService.swift

The largest and most complex migration. Bookmarks go into both the items table and the bookmarks detail table. Tags get extracted into tags + item_tags. Labels go into item_labels. Dismissed labels go into dismissed_labels.

- [ ] **Step 1: Add bookmark insert/update/delete methods for SQLite**

Each bookmark write must (inside a single withTransaction):
1. INSERT OR REPLACE into items (id, type='bookmark', title, created_at, updated_at, folder_id, relative_path)
2. INSERT OR REPLACE into bookmarks (all bookmark-specific fields)
3. Sync item_labels: DELETE WHERE item_id = ?, then INSERT for each current labelID
4. Sync dismissed_labels: DELETE WHERE item_id = ?, then INSERT for each current dismissedLabelID
5. Sync item_tags: find-or-create tag rows in tags table, DELETE FROM item_tags WHERE item_id = ?, then INSERT for each current tag

- [ ] **Step 2: Add bookmark load method**

Query: SELECT from items JOIN bookmarks WHERE type = 'bookmark', then for each row load its labels (SELECT label_id FROM item_labels WHERE item_id = ?) and tags (SELECT t.name FROM item_tags it JOIN tags t ON t.id = it.tag_id WHERE it.item_id = ?). Assemble into Bookmark model objects.

- [ ] **Step 3: Switch VaultBookmarkService to SQLite persistence**

Replace JSON load in init() with SQLite load. Replace persist() calls with SQLite writes. Keep sidecar writes for rebuild recoverability.

- [ ] **Step 4: Verify parity**

- Same bookmark count
- Same IDs, titles, URLs
- Same folder assignments
- Same tags and labels
- Same notes and AI summaries
- Same enrichment status
- Same relative paths
- CLI bookmark list --json output matches
- CLI bookmark add, bookmark update, bookmark delete work correctly

- [ ] **Step 5: Commit**

Message: feat(db): migrate VaultBookmarkService to SQLite persistence

---

## Tasks 5-9: Remaining Type Migrations

Each follows the identical pattern from Task 4, adapted for the type's specific fields.

### Task 5: Notes Migration
- Table: items + notes
- Key: content mirrors .md file body, is_pinned is DB-only metadata
- Must add note UUID sidecar persistence (notes currently have no file-level UUID)
- Commit: feat(db): migrate NotesStorage to SQLite persistence

### Task 6: Todos Migration
- Table: items + todos
- Key: checklist stored as JSON blob, linkedEntities extracted to item_links
- .ics files already have UID matching items.id
- Commit: feat(db): migrate TodoCardStorage to SQLite persistence

### Task 7: Events Migration
- Table: items + events
- Key: recurrence_rule and surfacing_rules as JSON blobs, linkedEntities to item_links
- .ics files already have UID matching items.id
- Commit: feat(db): migrate DateCardStorage to SQLite persistence

### Task 8: Contacts Migration
- Table: items + contacts
- Key: linkedEntities to item_links, .vcf files have UID
- Display name is items.title, not duplicated
- Commit: feat(db): migrate ContactStorage to SQLite persistence

### Task 9: Vault Files Migration
- Table: items + vault_files
- CRITICAL: Must migrate from path-derived IDs to stable UUIDs
- Create UUID persistence sidecar at .cider/vault-files/id-map.json
- Update VaultFileService.assignFile() to preserve UUID across moves
- Commit: feat(db): migrate VaultFileService to SQLite persistence with stable UUIDs

### Task 10: Sessions Migration
- Standalone sessions table (not in items)
- Straightforward JSON to SQLite swap
- Non-recoverable if DB is deleted (acceptable)
- Commit: feat(db): migrate BrowserSessionStorage to SQLite persistence

### Task 11: Trash Migration
- trash table with JSON payload column
- Depends on all other types being migrated first
- Commit: feat(db): migrate TrashStorage to SQLite persistence

---

## Task 12: Startup Reconciliation

**Files:**
- Create: Sources/Cider/Database/VaultReconciler.swift

This is the system that keeps the DB in sync with the filesystem on every launch.

- [ ] **Step 1: Write VaultReconciler.swift**

Implements the 8-step reconciliation from the spec:
1. DB is already loaded by services at this point
2. Scan vault directory tree (walk all files)
3. Match files to DB rows by relative_path
4. For unmatched files: check embedded UUID/sidecar, try to reconnect moved files
5. Adopt orphans (new files with no DB row) -- create items + detail rows
6. Detect modified files (compare file mtime vs updated_at in DB, re-parse if newer)
7. Remove stale rows (DB rows whose files no longer exist on disk)
8. Services re-publish @Published arrays

Output: a diff struct with newFiles, movedFiles, modifiedFiles, deletedIDs. Each service applies the relevant changes.

- [ ] **Step 2: Integrate reconciler into app startup**

Call VaultReconciler.reconcile() after all services have loaded from SQLite, before UI renders. This replaces the current orphan adoption system.

- [ ] **Step 3: Test reconciliation scenarios**

- File added externally while app was closed -- adopted
- File moved in Finder -- path updated, ID preserved
- File deleted externally -- row removed
- File content edited externally -- re-parsed, DB updated
- No changes -- no DB writes (fast path)

- [ ] **Step 4: Commit**

Message: feat(db): add startup vault reconciliation (filesystem to SQLite sync)

---

## Task 13: Remove JSON Persistence

**Files:**
- Modify: All storage services
- Delete: JSON file handling code

After all services are on SQLite and reconciliation works:

- [ ] **Step 1: Remove JSON load/persist methods from all storage services**
- [ ] **Step 2: Remove JSON snapshot structs (e.g. CardLabelsSnapshot)**
- [ ] **Step 3: Keep sidecar writes for bookmarks** (needed for rebuild recoverability)
- [ ] **Step 4: Keep .ics/.vcf file writes** (these are the source-of-truth artifacts)
- [ ] **Step 5: Verify the app works with no JSON index files present**
- [ ] **Step 6: Commit**

Message: refactor(db): remove JSON index persistence, SQLite is now primary

---

## Execution Notes

- Build check: Run swift build after every task to catch compilation errors early.
- Dual-write phase: Keep it short per service. Add SQLite, verify parity, remove JSON -- ideally within the same session per service.
- Sidecar writes stay: Bookmark sidecars are still written alongside SQLite. They serve as the file-level backup for rebuild recoverability.
- No UI changes: The @Published arrays stay the same. Views do not know or care about SQLite.
- Label backup: On every label mutation, also write .cider/labels-backup.json for rebuild recoverability.
- Testing: Use Swift Testing framework (@Suite, @Test, #expect). Create temp directories for each test, clean up in defer blocks.
