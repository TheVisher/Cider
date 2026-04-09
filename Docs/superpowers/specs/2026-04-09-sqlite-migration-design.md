# Cider SQLite Migration Design

**Date:** 2026-04-09
**Status:** Approved design, pending implementation plan

## Summary

Migrate Cider's metadata/index persistence from per-type JSON files to a single SQLite database. Files on disk remain the source of truth for user content. SQLite becomes the hidden index and intelligence layer.

## Architecture Decisions

### Approach A: In-memory arrays, SQLite replaces persistence only

- Storage services keep `@Published private(set) var items: [Model]` arrays
- On startup: load from SQLite, then reconcile against vault filesystem (see Startup Reconciliation)
- On mutation: update in-memory array AND write to SQLite
- UI code does not change
- SQLite is the persistence layer, not the query engine for views (yet)

### Unified `items` table + per-type detail tables

- One `items` table with universal fields (identity, type, title, timestamps, folder, path)
- Per-type detail tables (`bookmarks`, `notes`, `todos`, etc.) with type-specific fields
- Shared join tables for cross-type features (tags, labels, relationships)
- Cross-type queries (search, folder contents, labels) use `items` directly

### Key Rules

- `folder_id = NULL` means Inbox/unfiled. Inbox is not a real folder row.
- `items.title` is the canonical display title for all types. No duplicate name fields in detail tables.
- Kanban boards stay in YAML files (different ID system, not part of the library graph).
- Sessions are DB-only metadata (not file-backed). See Sessions section.

### Identity Contract

Every item gets a **stable UUID** that survives file moves and renames.

- `items.id` is a random UUID assigned at creation time. It never changes.
- `items.relative_path` changes when a file moves. `items.id` does not.
- File-backed items embed their UUID in the artifact or sidecar:
  - Bookmarks: UUID stored in folder sidecar JSON (already exists)
  - Notes: **must add UUID persistence.** Current UUIDs live only in the JSON note index. Once that index is removed, notes have no file-level identity. During migration, persist note UUIDs via a per-directory sidecar JSON (matching the bookmark sidecar pattern) so rebuild can recover note identity.
  - Todos/Events: `UID` field in `.ics` file (already exists, use as `items.id`)
  - Contacts: `UID` field in `.vcf` file (already exists, use as `items.id`)
  - Vault files: **must migrate from path-derived IDs to stable UUIDs.** Current `stableID(for: relativePath)` must be replaced. During migration, assign a random UUID and persist it in a sidecar or extended attribute.
- On rebuild from disk, the embedded/sidecar UUID reconnects the file to its prior identity, preserving labels, links, and trash references.

**Migration note for vault files:** Current vault file IDs are derived from `relativePath` via a hash. Moving a file changes its ID, which cascades through `item_labels`, `item_links`, and `trash`. The migration must:
1. Assign each vault file a random UUID
2. Persist the UUID in a sidecar file (`.cider/vault-files/id-map.json` or per-directory sidecar)
3. Update `VaultFileService.assignFile()` to preserve the UUID across moves

### Startup Reconciliation

On every launch, after loading the SQLite database into memory, Cider must reconcile the database against the vault filesystem. This preserves the "files are source of truth" guarantee.

**Reconciliation steps:**

1. **Open DB** — load SQLite, populate in-memory arrays
2. **Scan vault** — walk the vault directory tree, discover all files
3. **Match files to DB rows** — by `relative_path` first, then by embedded UUID/sidecar for moved files
4. **Adopt orphans** — files on disk with no DB row get new items + detail rows (same as current orphan adoption)
5. **Update moved files** — files whose path changed get their `relative_path` updated in the DB
6. **Detect modified files** — compare file modification time (mtime) against `updated_at` in DB. If the file is newer, re-parse it and update the DB row. This catches external edits to `.md`, `.ics`, `.vcf`, and sidecar files made while Cider was closed.
7. **Remove stale rows** — DB rows whose files no longer exist on disk get removed (or marked stale)
8. **Publish arrays** — push reconciled data to `@Published` arrays for UI

This is the same logic the current file watcher and orphan adoption system performs, adapted for SQLite instead of JSON. The reconciliation must run before any UI renders.

**Important:** Reconciliation is primarily a diff operation. Steps 1-5 and 7 compare known paths/IDs against filesystem state. Step 6 (modified file detection) only re-parses files whose mtime is newer than the DB timestamp — not every file on every launch.

## Schema

### Core Table

```sql
CREATE TABLE items (
    id            TEXT PRIMARY KEY,
    type          TEXT NOT NULL,       -- 'bookmark','note','todo','event','contact','vault_file'
    title         TEXT NOT NULL,
    created_at    REAL NOT NULL,       -- Unix timestamp (Swift TimeInterval)
    updated_at    REAL NOT NULL,
    folder_id     TEXT REFERENCES folders(id),
    relative_path TEXT                 -- vault-relative file path (nullable for DB-only items)
);
```

Note: `session` is not in the `items.type` enum. Sessions are stored in their own table outside the unified model (see Sessions section).

### Per-Type Detail Tables

#### bookmarks

```sql
CREATE TABLE bookmarks (
    item_id                 TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    url                     TEXT NOT NULL,
    -- User-owned fields
    notes                   TEXT NOT NULL DEFAULT '',
    notes_manually_set      INTEGER NOT NULL DEFAULT 0,
    title_manually_set      INTEGER NOT NULL DEFAULT 0,
    -- AI-owned fields
    ai_summary              TEXT,
    enrichment_status       TEXT,          -- 'none','partial','complete'
    last_enriched_at        REAL,
    ocr_text                TEXT,
    -- Derived/cache fields (rebuildable via re-enrichment)
    dominant_colors         TEXT,          -- JSON array: '["#FF0000","#00FF00"]'
    media_type              TEXT,          -- 'image','gif','video'
    thumbnail_relative_path TEXT,
    thumbnail_remote_url    TEXT,
    original_image_path     TEXT,
    carousel_image_paths    TEXT,          -- JSON array
    reader_unavailable      INTEGER,       -- derived: true when Readability.js fails
    preferred_hero_mode     TEXT           -- 'thumbnail','reader','web'
);
```

Field ownership:
- **User-owned:** `notes`, `notes_manually_set`, `title_manually_set`
- **AI-owned:** `ai_summary`, `enrichment_status`, `last_enriched_at`, `ocr_text`
- **Derived/cache:** `dominant_colors`, `media_type`, `thumbnail_*`, `original_image_path`, `carousel_image_paths`, `reader_unavailable`, `preferred_hero_mode`

#### notes

```sql
CREATE TABLE notes (
    item_id   TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    content   TEXT NOT NULL DEFAULT '',   -- full markdown body (mirrored from .md file)
    is_pinned INTEGER NOT NULL DEFAULT 0
);
```

`content` is a cached copy of the `.md` file body. Rebuildable from disk.

#### todos

```sql
CREATE TABLE todos (
    item_id      TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    details      TEXT NOT NULL DEFAULT '',   -- primary task description
    due_date     REAL,
    priority     TEXT,                       -- 'low','medium','high'
    is_completed INTEGER NOT NULL DEFAULT 0,
    completed_at REAL,
    notes        TEXT NOT NULL DEFAULT '',   -- supporting comments/context
    checklist    TEXT                        -- JSON: TodoChecklistItem array (card-local, never queried independently)
);
```

#### events

```sql
CREATE TABLE events (
    item_id         TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    details         TEXT NOT NULL DEFAULT '',
    start_at        REAL NOT NULL,
    end_at          REAL,
    all_day         INTEGER NOT NULL DEFAULT 0,
    location        TEXT NOT NULL DEFAULT '',
    amount          REAL,
    recurrence_rule TEXT,                    -- JSON: {"frequency":"weekly","interval":1,"endDate":...}
    is_completed    INTEGER NOT NULL DEFAULT 0,
    completed_at    REAL,
    surfacing_rules TEXT                     -- JSON array (app-specific policy)
);
```

#### contacts

```sql
CREATE TABLE contacts (
    item_id            TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    relationship_label TEXT NOT NULL DEFAULT '',
    birthday           REAL,
    notes              TEXT NOT NULL DEFAULT '',
    email              TEXT NOT NULL DEFAULT '',
    phone              TEXT NOT NULL DEFAULT '',
    address            TEXT NOT NULL DEFAULT '',
    has_avatar         INTEGER NOT NULL DEFAULT 0
);
```

Contact display name is `items.title`. No separate `display_name` field.

#### vault_files

```sql
CREATE TABLE vault_files (
    item_id         TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    filename        TEXT NOT NULL,      -- raw filesystem name (e.g. "IMG_1234.jpg")
    file_type       TEXT NOT NULL,      -- 'image','pdf','video','audio','document','archive','unknown'
    file_size       INTEGER NOT NULL,
    notes           TEXT NOT NULL DEFAULT '',
    ocr_text        TEXT,
    dominant_colors TEXT                -- JSON array
);
```

`filename` = raw filesystem artifact name. `items.title` = user-facing display name (may differ if renamed).

### Sessions (DB-only, outside unified model)

Sessions are browser tab snapshots. They are **not file-backed** — no vault file artifact exists for them. They do not participate in the unified `items` table.

```sql
CREATE TABLE sessions (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    source_browser_id   TEXT,
    source_browser_name TEXT,
    tabs                TEXT,           -- JSON array: [{id, url, title}]
    folder_id           TEXT REFERENCES folders(id),
    label_ids           TEXT,           -- JSON array of UUID strings
    created_at          REAL NOT NULL,
    updated_at          REAL NOT NULL
);
```

Sessions are non-recoverable if the database is deleted. This is acceptable — they are ephemeral snapshots, not long-lived knowledge artifacts.

**Cross-type query impact:** Because sessions are outside the `items` table, they do not appear in unified cross-type queries (folder contents, label filters). The search service must query the `sessions` table separately and merge results. This is intentional for v1 — sessions are second-class citizens in the unified model. If sessions need full cross-type participation later, they can be promoted to `items`.

### Shared Tables

#### folders

```sql
CREATE TABLE folders (
    id                   TEXT PRIMARY KEY,
    relative_path        TEXT NOT NULL UNIQUE,
    created_at           REAL NOT NULL,
    updated_at           REAL NOT NULL,
    icon                 TEXT,
    cover_image_path     TEXT,
    cover_image_offset_y REAL
);
```

#### labels

```sql
CREATE TABLE labels (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    color_hex  TEXT NOT NULL,
    kind       TEXT NOT NULL DEFAULT 'custom',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
```

#### item_labels

```sql
CREATE TABLE item_labels (
    item_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, label_id)
);
```

#### dismissed_labels

```sql
CREATE TABLE dismissed_labels (
    item_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, label_id)
);
```

#### tags

```sql
CREATE TABLE tags (
    id   TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE item_tags (
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, tag_id)
);
```

#### item_links

```sql
CREATE TABLE item_links (
    source_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    target_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    link_type  TEXT NOT NULL,          -- 'linked','related','mentioned'
    created_at REAL NOT NULL,
    PRIMARY KEY (source_id, target_id, link_type)
);
```

Future addition (not v1): `confidence REAL`, `source TEXT` for AI-generated vs user-created links.

#### trash

```sql
CREATE TABLE trash (
    id                TEXT PRIMARY KEY,
    item_id           TEXT NOT NULL,
    item_type         TEXT NOT NULL,
    title             TEXT NOT NULL,
    original_folder_id TEXT,
    deleted_at        REAL NOT NULL,
    payload           TEXT NOT NULL    -- JSON snapshot for full restoration
);
```

### Indexes

```sql
CREATE INDEX idx_items_type        ON items(type);
CREATE INDEX idx_items_folder      ON items(folder_id);
CREATE INDEX idx_items_created     ON items(created_at);
CREATE INDEX idx_items_updated     ON items(updated_at);
CREATE UNIQUE INDEX idx_items_path ON items(relative_path) WHERE relative_path IS NOT NULL;
CREATE INDEX idx_item_labels_label ON item_labels(label_id);
CREATE INDEX idx_item_tags_tag     ON item_tags(tag_id);
CREATE INDEX idx_item_links_target ON item_links(target_id);
CREATE INDEX idx_bookmarks_url     ON bookmarks(url);
CREATE INDEX idx_bookmarks_enrich  ON bookmarks(enrichment_status);
CREATE INDEX idx_todos_completed   ON todos(is_completed);
CREATE INDEX idx_events_start      ON events(start_at);
```

### JSON Blob Fields

These store nested, card-local data that is loaded/saved as a unit:

| Table | Column | Contents |
|-------|--------|----------|
| bookmarks | dominant_colors | `["#hex",...]` |
| bookmarks | carousel_image_paths | `["path",...]` |
| todos | checklist | `[{id, title, isCompleted, subtasks:[...]}]` |
| events | recurrence_rule | `{frequency, interval, endDate}` |
| events | surfacing_rules | `[{id, type, integerValue, isEnabled}]` |
| sessions | tabs | `[{id, url, title}]` |
| sessions | label_ids | `["uuid",...]` |
| vault_files | dominant_colors | `["#hex",...]` |

## Not Migrated (v1)

| System | Reason | Current Storage |
|--------|--------|-----------------|
| Kanban boards | Different ID system, not part of library graph | `.cider/boards/*.yaml` |
| Whiteboards | Canvas data, not relational | `.cider/whiteboards/` |
| Clipboard history | Ephemeral, high-churn | `.cider/clipboard/` |
| AI conversations | Separate concern | `.cider/ai-chat/` |
| Saved views | App config, not vault data | `.cider/saved-views/` |
| Card stacks | App config | In-memory + JSON |

## Rebuild Story

If the SQLite database is deleted, Cider must reconstruct a usable index from vault files.

### What is embedded in files today

Understanding what metadata is already persisted in vault files is critical for the rebuild story.

| File type | Embedded metadata |
|-----------|------------------|
| `.webloc` + sidecar JSON | UUID, title, tags, labelIDs, **dismissedLabelIDs**, notes, aiSummary, ocrText, dominantColors, mediaType, thumbnails, timestamps |
| `.md` files | Content (the file itself). Title from filename. Note metadata (labels, pinned, folderID) in note index only. |
| `.ics` (VTODO) | UID (= item UUID), summary, description, due, priority, status, `X-CIDER-LABEL`, `X-CIDER-LINKED` |
| `.ics` (VEVENT) | UID (= item UUID), summary, dtstart, dtend, location, rrule, `X-CIDER-LABEL`, `X-CIDER-LINKED` |
| `.vcf` | UID, FN, EMAIL, TEL, ADR, BDAY, NOTE, `X-CIDER-LABEL`, `X-CIDER-LINKED`, `X-CIDER-RELATIONSHIP`, `X-CIDER-HAS-AVATAR` |
| Vault files (images, PDFs, etc.) | No embedded metadata. Filename only. |

### Fully recoverable from disk

| Data | Source |
|------|--------|
| Bookmarks (full) | Parse `.webloc` URL + folder sidecar JSON (contains all metadata including UUID, tags, labels, AI summary, notes) |
| Notes (core) | Parse `.md` files — filename = title, content = body |
| Todos (full) | Parse `.ics` VTODO — includes UID, labels (`X-CIDER-LABEL`), links (`X-CIDER-LINKED`) |
| Events (full) | Parse `.ics` VEVENT — includes UID, labels, links |
| Contacts (full) | Parse `.vcf` — includes UID, labels, links |
| Vault files (partial) | Scan filesystem — filename, size, type. No UUID recovery without sidecar. |
| Folders | Scan directory structure |

### Partially recoverable

| Data | What's recoverable | What's lost |
|------|-------------------|-------------|
| Labels (definitions) | Backed up to `.cider/labels-backup.json` | Nothing, if backup is current |
| Labels (assignments) | Bookmarks: from sidecar. Todos/Events/Contacts: from `X-CIDER-LABEL` in files | Note label assignments (index-only) |
| Tags | Bookmark tags from sidecar | Tag definitions table (recreated from unique tag strings) |
| Relationships | Todos/Events/Contacts: from `X-CIDER-LINKED` in files | Bookmark-to-item links (if any) |
| Vault file identity | If sidecar/id-map exists | UUID lost without sidecar → new UUID assigned, old labels/links orphaned |

### Not recoverable (must re-create)

| Data | Notes |
|------|-------|
| AI enrichment | Must re-enrich (but bookmark sidecars already persist aiSummary, so most is recoverable) |
| Sessions | DB-only, no file artifact |
| Trash | Deleted items are gone |
| Note metadata | Pinned state, note-specific labels (index-only today, until note sidecar is added) |

Note: Dismissed labels for bookmarks ARE recoverable from sidecars (`dismissedLabelIDs` is persisted).

### Label backup strategy

Label definitions represent user intent and must survive a database rebuild. On every label mutation, persist a backup to `.cider/labels-backup.json` with exact IDs. On rebuild, restore from this file. IDs must match exactly so file-embedded `X-CIDER-LABEL` UUIDs resolve correctly.

## Database Location

`.cider/cider.db` — inside the hidden metadata directory, consistent with existing `.cider/` convention.

## Migration Order

Migrate one storage service at a time. Recommended order (least dependencies first):

1. **Database bootstrap** — create `.cider/cider.db`, schema creation, connection management, schema versioning
2. **Labels** — no dependencies, small dataset, validates the SQLite layer works
3. **Folders** — needed as FK target for everything else
4. **Bookmarks** — largest dataset, most fields, best stress test
5. **Notes** — simple, validates content mirroring
6. **Todos** — medium complexity (checklist JSON)
7. **Events** — medium complexity (recurrence, surfacing rules)
8. **Contacts** — simple, small dataset
9. **Vault files** — includes UUID stabilization (migrate from path-derived IDs)
10. **Trash** — depends on all other types being migrated
11. **Tags + item_tags** — extracted from bookmark tags during bookmark migration
12. **item_links** — extracted from linkedEntities arrays during todo/event/contact migration
13. **Sessions** — standalone table, no items dependency
14. **Startup reconciliation** — implement filesystem ↔ DB reconcile pass

Each migration step:
1. Add SQLite read/write alongside existing JSON (keep dual-write phase short — verification only, not a comfortable intermediate state)
2. Verify parity with concrete checklist per type:
   - Same item count
   - Same IDs
   - Same folder assignments
   - Same tags/labels
   - Same notes/ai_summary/enrichment fields
   - Same relative paths
   - Same CLI-visible behavior
3. Remove JSON persistence
4. Delete old JSON file handling code

## Shared Database Layer

All storage services must use a single shared database layer rather than each inventing its own SQLite access patterns. This layer provides:

- **Connection management** — single shared `SQLiteDatabase` instance
- **Schema versioning** — migration table tracking applied schema versions
- **Transaction helpers** — `withTransaction { }` for atomic multi-table writes
- **Common row encoding/decoding** — shared patterns for UUID ↔ TEXT, Date ↔ REAL, arrays ↔ JSON TEXT
- **Rebuild utilities** — shared file-scanning and item-creation logic for the reconciliation pass

This must be built first (step 1) before any service migration begins.

## Future Evolution (not v1)

- `item_links.confidence` and `item_links.source` for AI-generated vs user links
- `folders.parent_id` for faster tree queries
- FTS5 virtual table for full-text search across titles, notes, summaries
- `dismissed_labels.dismissed_at` and `dismissed_labels.source`
- Separate `bookmark_media` table if bookmark columns get unwieldy
- Query-driven UI (Approach B) if memory becomes a bottleneck
- Sessions promoted to unified `items` model if they need cross-type features
