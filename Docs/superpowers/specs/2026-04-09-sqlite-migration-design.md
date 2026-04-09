# Cider SQLite Migration Design

**Date:** 2026-04-09
**Status:** Approved design, pending implementation plan

## Summary

Migrate Cider's metadata/index persistence from per-type JSON files to a single SQLite database. Files on disk remain the source of truth for user content. SQLite becomes the hidden index and intelligence layer.

## Architecture Decisions

### Approach A: In-memory arrays, SQLite replaces persistence only

- Storage services keep `@Published private(set) var items: [Model]` arrays
- On startup: load from SQLite instead of JSON
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
- All v1 items are file-backed. No `source_kind` column yet.
- `items.title` is the canonical display title for all types. No duplicate name fields in detail tables.
- Kanban boards stay in YAML files (different ID system, not part of the library graph).

## Schema

### Core Table

```sql
CREATE TABLE items (
    id            TEXT PRIMARY KEY,
    type          TEXT NOT NULL,       -- 'bookmark','note','todo','event','contact','session','vault_file'
    title         TEXT NOT NULL,
    created_at    REAL NOT NULL,       -- Unix timestamp (Swift TimeInterval)
    updated_at    REAL NOT NULL,
    folder_id     TEXT REFERENCES folders(id),
    relative_path TEXT                 -- vault-relative file path (nullable)
);
```

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

#### sessions

```sql
CREATE TABLE sessions (
    item_id             TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    source_browser_id   TEXT,
    source_browser_name TEXT,
    tabs                TEXT            -- JSON array: [{id, url, title}] (loaded as unit, never queried individually)
);
```

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

### Fully recoverable from disk

| Data | Source |
|------|--------|
| Bookmarks (core) | Parse `.webloc` files — URL + filename |
| Notes (core) | Parse `.md` files — filename = title, content = body |
| Contacts | Parse `.vcf` files — vCard fields |
| Todos | Parse `.ics` VTODO files |
| Events | Parse `.ics` VEVENT files |
| Vault files | Scan filesystem — filename, size, type |
| Folders | Scan directory structure |

### Partially recoverable

| Data | What's recoverable | What's lost |
|------|-------------------|-------------|
| Labels | Definitions backed up to `.cider/labels-backup.json` | Assignments if backup is stale |
| Tags | Bookmark tags only if stored in webloc sidecar | Tag-item associations |

### Not recoverable (must re-create)

| Data | Recovery path |
|------|--------------|
| AI enrichment | Re-enrich (ai_summary, ocr_text, dominant_colors) |
| Relationships (item_links) | Must be re-created by user or AI |
| Trash | Deleted items are gone |
| Dismissed labels | Lost |

### Label backup strategy

Label definitions represent user intent and must survive a database rebuild. On every label mutation, persist a backup to `.cider/labels-backup.json`. On rebuild, restore from this file.

## Database Location

`.cider/cider.db` — inside the hidden metadata directory, consistent with existing `.cider/` convention.

## Migration Order

Migrate one storage service at a time. Recommended order (least dependencies first):

1. **Labels** — no dependencies, small dataset, validates the SQLite layer works
2. **Folders** — needed as FK target for everything else
3. **Bookmarks** — largest dataset, most fields, best stress test
4. **Notes** — simple, validates content mirroring
5. **Todos** — medium complexity (checklist JSON)
6. **Events** — medium complexity (recurrence, surfacing rules)
7. **Contacts** — simple, small dataset
8. **Vault files** — simple
9. **Sessions** — simple
10. **Trash** — depends on all other types being migrated
11. **Tags + item_tags** — extracted from bookmark tags during bookmark migration
12. **item_links** — extracted from linkedEntities arrays during todo/event/contact migration

Each migration step:
1. Add SQLite read/write alongside existing JSON
2. Verify parity
3. Remove JSON persistence
4. Delete old JSON file handling code

## Future Evolution (not v1)

- `item_links.confidence` and `item_links.source` for AI-generated vs user links
- `folders.parent_id` for faster tree queries
- FTS5 virtual table for full-text search across titles, notes, summaries
- `dismissed_labels.dismissed_at` and `dismissed_labels.source`
- Separate `bookmark_media` table if bookmark columns get unwieldy
- Query-driven UI (Approach B) if memory becomes a bottleneck
