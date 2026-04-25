# Storage Standard

> Status note: this document describes the legacy and transitional file/index model that Cider has used during the per-file and SQLite migration work. For the active target architecture, see [STORAGE_DOCTRINE.md](./STORAGE_DOCTRINE.md). Where this document conflicts with the doctrine, the doctrine wins.

> This is the definitive reference for how Cider stores ALL data on disk — user content (standard files) and internal app data (hidden `.cider/` directory). **Every card type** must follow the per-file pattern. No exceptions.
>
> *Consolidates the former PER_FILE_STORAGE.md and VAULT_STORAGE.md.*

## Core Principle

> The user's data lives as real, standard files they can see in Finder. App metadata lives hidden in `.cider/`.

## File Layout

```
~/CiderVault/
├── .cider/                              # Hidden — app metadata only
│   ├── {type}/
│   │   ├── _cider_{type}_index.json     # Index: UUID → metadata cache
│   │   ├── .assets/                     # Binary assets (avatars, attachments)
│   │   └── .trash/                      # Trashed files + manifest
│   └── ...
├── Inbox/                               # Unfiled content files (visible)
│   ├── Bookmarks/                       # .webloc files
│   ├── Notes/                           # .md files
│   ├── Contacts/                        # .vcf files
│   ├── Todos/                           # .ics files (VTODO)
│   └── Date Cards/                      # .ics files (VEVENT)
├── {User Folder}/                       # Filed content files
│   ├── My Note.md
│   ├── John Smith.vcf
│   └── Dentist Appointment.ics
└── CLAUDE.md
```

## Standard File Formats

| Card Type    | Extension | Format         | Standard         |
|-------------|-----------|----------------|------------------|
| Bookmarks   | `.webloc` | Apple URL plist| macOS native     |
| Notes       | `.md`     | Markdown       | CommonMark       |
| Contacts    | `.vcf`    | vCard 3.0      | RFC 6350         |
| Todos       | `.ics`    | iCalendar      | RFC 5545 (VTODO) |
| Date Cards  | `.ics`    | iCalendar      | RFC 5545 (VEVENT)|

**Why standard formats?** A `.vcf` can be dragged into Apple Contacts. An `.ics` can be double-clicked to add to Calendar. The vault isn't a proprietary database — it's a folder of real files.

### Cider-Specific Fields

Standard formats don't cover everything Cider tracks (labels, linked entities, etc.). These go in `X-CIDER-*` extension properties inside the file:

```
X-CIDER-ID:550e8400-e29b-41d4-a716-446655440000
X-CIDER-LABEL:uuid1,uuid2
X-CIDER-LINKED:dateCard:uuid3,contact:uuid4
X-CIDER-CREATED:20260101T120000Z
X-CIDER-UPDATED:20260312T150000Z
```

Spec-compliant parsers (Apple Contacts, Google Calendar) ignore `X-` properties, so the files remain fully interoperable.

## The Index File

Each type has an index at `.cider/{type}/_cider_{type}_index.json`. The index is a **performance cache**, not the source of truth. If deleted, the app rebuilds it by scanning files.

### What goes in the index

Only fields needed for **fast startup** (sort, filter, display) without parsing every file:

```json
{
  "version": 1,
  "items": {
    "550e8400-...": {
      "filename": "John Smith.vcf",
      "folderID": null,
      "labelIDs": ["uuid1"],
      "createdAt": "2026-01-01T12:00:00Z"
    }
  }
}
```

Type-specific "hot" fields for sort/filter (without parsing every file on startup):

| Type       | Extra index fields                        |
|-----------|-------------------------------------------|
| Contacts  | (none — displayName comes from filename)  |
| Todos     | `isCompleted`, `dueDate`, `priority`      |
| Date Cards| `startAt`, `isCompleted`                  |
| Bookmarks | `urlString`, `tags`                       |
| Notes     | (none — title comes from filename)        |

### What stays file-only

Everything else: full descriptions, checklist items, recurrence rules, notes, subtasks, locations, amounts. Parsed on demand when the user opens a card.

## Filename Convention

- Filename = sanitized title + extension: `John Smith.vcf`, `Buy Groceries.ics`
- UUID is NOT in the filename — the index maps UUID → filename
- On collision: append ` 2`, ` 3`, etc.
- When a card is renamed, the file is renamed and the index is updated

## Folder Assignment = File Move

Assigning a card to a folder physically moves the file:

```
Unfiled:   ~/CiderVault/Inbox/Contacts/John Smith.vcf
In "Work": ~/CiderVault/Work/John Smith.vcf
```

The index entry's `folderID` is updated. The `filename` stays the same.

### Resolving a file's location

```
if folderID == nil → Inbox/{Type}/{filename}
else → {folder.relativePath}/{filename}   (from VaultFolderService)
```

## Trash Pattern

1. Move content file → `.cider/{type}/.trash/{filename}`
2. Move associated assets (avatars, etc.) → `.cider/{type}/.trash/`
3. Add entry to `.trash/_cider_trash_manifest.json` with `filename` + `folderID`
4. Remove from in-memory array and index

On restore: move file back to correct directory, re-add to index.

The trash manifest only stores `filename` and `folderID` — the file itself contains all data.

## Storage Class Template

Every card type's storage class follows this shape:

```swift
@MainActor
final class {Type}Storage: ObservableObject {
    static let shared = {Type}Storage()

    @Published private(set) var items: [{Model}] = []

    // MARK: - Index
    private struct IndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        // + type-specific hot fields
    }
    private var index: [UUID: IndexEntry] = [:]

    // MARK: - CRUD
    func create(...) -> {Model}                   // Write file + add to index
    func update(_ item: {Model})                  // Rewrite file + update index
    func delete(_ id: UUID)                       // Move to .trash + update index
    func assign(_ id: UUID, toFolder: UUID?)      // Move file + update index

    // MARK: - Serialization (type-specific)
    private func writeFile(for item: {Model}, to url: URL)
    private func parseFile(at url: URL) -> {Model}?

    // MARK: - Index I/O
    private func saveIndex()
    private static func loadAndScan(...) -> ScanResult

    // MARK: - Restore
    func restoreFromTrash(filename: String, folderID: UUID?, ...)
}
```

### Required methods

| Method | Purpose |
|--------|---------|
| `writeFile(for:to:)` | Serialize model → standard format (.vcf/.ics/.md) |
| `parseFile(at:)` | Parse standard format → model |
| `loadAndScan(...)` | Background-safe: load index, scan filesystem, reconcile |
| `resolveFileURL(for:)` | Compute absolute path from folderID + filename |
| `saveIndex()` | Persist the index to `.cider/{type}/` |

## Adding a New Card Type

When implementing a new card type (e.g., Books):

1. **Choose the standard format** (or JSON if no standard exists)
2. **Add to `StorageType`** enum with `ciderSubpath` and `inboxSubfolderName`
3. **Write a serializer** — `{Format}Serializer.swift` with `write()` and `parse()`
4. **Create the storage class** following the template above
5. **Update `StoragePaths.ensureVaultStructure()`** to create the Inbox subfolder
6. **Update `TrashStorage`** with trash/restore for the new type
7. **Update `VaultIndexService`** to include the new type in rebuilds
8. **Write migration** if converting from an existing format

## Migration Pattern

One-time migrations are gated by boolean flags in `CiderConfig`:

```swift
var didMigrate{Type}ToPerFile: Bool
```

Each type migrates independently. Steps:

1. Read old monolithic JSON
2. Write individual files to `Inbox/{Type}/`
3. Build and save the index
4. Rename old JSON to `_cider_{type}_legacy.json` (backup)
5. Set flag in CiderConfig

Called from `AppDelegate` after `VaultStructureMigration` and before storage singletons initialize.

## Internal App Data (`.cider/` Directory)

All app-internal data lives inside `~/CiderVault/.cider/`, a hidden directory that macOS auto-hides from Finder. The vault root is reserved for user-visible folders only.

```
~/CiderVault/.cider/
├── bookmarks/           # Bookmark metadata + index
├── notes/               # Note metadata + index
├── contacts/            # Contact metadata
├── date-cards/          # Calendar-linked cards
├── labels/              # Label definitions
├── saved-views/         # Saved filter/sort configs
├── sources/             # Linked source definitions
├── stacks/              # Grouped collections
├── tags/                # Tag definitions
├── todos/               # Task items
├── clipboard/           # Clipboard history
├── whiteboards/         # Freeform canvas boards
├── sessions/            # Browsing session snapshots
├── boards/              # Kanban board YAML files
├── folder-kanban/       # Per-folder kanban board data
├── vault-files/         # Vault file metadata (images, PDFs, videos, docs)
├── folders/             # Folder metadata: index.json, covers/, .trash/
├── ai-chat/             # AI Chat conversation history per model
├── ai/                  # NL embedding vectors (embeddings.json)
├── ai-conversations/    # AI conversation history (persistent threads)
└── index.json           # Vault-wide item index
```

### How Paths Resolve

`StoragePaths.directoryURL(for:)` builds paths as `vaultRoot/.cider/{StorageType.ciderSubpath}`. The `ciderSubpath` property on `StorageType` maps each case to a lowercase, hyphenated name (e.g. `.dateCards` → `"date-cards"`, `.savedViews` → `"saved-views"`).

If a user has set a `directoryOverrides` entry in CiderConfig for a StorageType, that override takes precedence (absolute path).

### Why `.cider/`?

- macOS hides dotfiles from Finder by default — zero filtering code needed
- The vault root becomes purely user content
- VaultFolderService no longer needs a hardcoded list of internal directory names
- Adding new internal directories requires no code changes to filtering logic

### Vault Structure Migration

On first launch after the update, `VaultStructureMigration.migrateIfNeeded()` moves old top-level internal directories into `.cider/`. The migration is idempotent — skips sources that don't exist or destinations that already exist. Gated by `didMigrateVaultToCiderDir` flag in CiderConfig.

## File Watching (External Edit Detection)

All storage services watch their Inbox directories for external changes using `FSEventsWatcher` (wrapper over the FSEvents C API). When files are created, modified, or deleted externally — by Claude via iMessage, Finder, Apple Contacts, or any other tool — Cider detects the change and reloads live.

**Services with file watchers:**
- `VaultBookmarkService` — scans vault folders for added or moved `.webloc` files; the JSON index is cache-only and is not watched as an edit API
- `VaultFileService` — watches vault root for new images/PDFs/videos (filters out `.cider/` metadata writes)
- `TodoCardStorage` — watches `Inbox/Todos/` for new `.ics` VTODO files
- `DateCardStorage` — watches `Inbox/Date Cards/` for new `.ics` VEVENT files
- `ContactStorage` — watches `Inbox/Contacts/` for new `.vcf` files
- `NotesStorage` — uses `DispatchSource.fileSystemObject` on the notes directory
- `KanbanStorage` — watches `.cider/boards/` for YAML changes
- `VaultFolderService` — watches vault root for directory creates/renames/deletes

**Key patterns:**
- All watchers use `MainActor.assumeIsolated` in callbacks (FSEventsWatcher dispatches to main queue)
- `pendingRescan` flag prevents dropped events during active scans
- Bookmark mutations should go through app services or `cider-cli`; agents should not edit cache JSON

### Vault File Adoption (Live)

`VaultBookmarkService.adoptOrphanedVaultFiles()` runs on load and after file movement flows (debounced to at most once per 5 seconds). It scans vault folders **first** (authoritative for folder assignment), then `Inbox/Bookmarks/`, for `.webloc` files not already tracked in SQLite-backed state. Orphaned files are adopted as new bookmarks with the correct `folderID` based on their directory location. Files that have moved between folders also get their `folderID` updated. This means files created by agents, Finder drag-and-drop, or any external tool are picked up automatically.

URLs that were recently deleted (within the last 30 seconds) are skipped during adoption to prevent "zombie re-adoption" from duplicate `.webloc` files that haven't been cleaned up yet. This is tracked via `VaultBookmarkService.recentlyDeletedURLs`.

### Webloc Cleanup on Trash

When a bookmark is trashed, `VaultBookmarkService.deleteWeblocFileOnly(for:)` deletes only the `.webloc` file from the vault directory (not image assets — `TrashStorage` handles those). This prevents the adoption scan from re-creating the bookmark on next load. The bookmark's metadata and assets are moved to the appropriate trash directory for potential restore.

### Trash Restore Directory Resolution

When restoring a bookmark from trash, `TrashStorage.restoreBookmark` resolves the correct target directory based on the bookmark's `folderID`: if the bookmark belonged to a vault folder, it restores to that folder's path; otherwise it restores to `Inbox/Bookmarks/`. The trash directory itself is resolved by checking `Inbox/Bookmarks/.trash/` first, then falling back to the legacy `.cider/bookmarks/.trash/` path. Vault folder trash lives at `.cider/folders/.trash/{folder-uuid}/`.

---

## Bookmark File Migration (Monolithic JSON → Individual .webloc Files)

> **Status:** Runtime has moved to `.webloc` files plus SQLite-backed bookmark metadata. Legacy bookmark sidecars are transition-only backfill input.

### Rationale

The original bookmark storage used a single monolithic JSON file (`_cider_bookmarks_metadata.json`) for ALL bookmarks and folder definitions. Folders were virtual (UUIDs in an array, not directories on disk), creating a disconnect with `VaultFolderService` which uses actual directories. The migration moves each bookmark to an individual `.webloc` file in the vault folder tree while SQLite owns bookmark metadata. Folders become real directories. AI sorting becomes simple file movement.

### Target Architecture

```
~/CiderVault/
├── Bookmarks/                          # unfiled bookmarks live here
│   ├── YouTube - Some Video.webloc
│   └── Reddit - Front Page.webloc
├── Entertainment/                      # user folder (real directory)
│   ├── .thumbnails/                   # thumbnails for items in this folder
│   │   └── <UUID>.png
│   ├── .originals/                    # full-size images
│   │   └── <UUID>.jpg
│   ├── Netflix - A Show.webloc
│   └── Videos/                        # sub-folder
│       └── TikTok - Funny Clip.webloc
└── ...
```

### Key Decisions

**1. `.webloc` as the bookmark file**
- macOS native format (XML plist with URL key)
- Double-click opens in browser
- Drag from browser into Cider folder = instant bookmark
- Finder shows site favicon
- Only stores the URL — lightweight, portable
- When a bookmark's URL is edited, `VaultBookmarkService.updateURL` rewrites the `.webloc` plist on disk to stay in sync

**2. SQLite owns bookmark metadata**
- `.webloc` stores the URL artifact
- SQLite stores bookmark metadata (title, notes, tags, labels, summaries, image references, AI fields, identity)
- legacy bookmark sidecars may still be read during transition, but they are no longer the normal runtime source of truth

**3. Thumbnails/originals move with bookmarks**
- Each folder has its own `.thumbnails/` and `.originals/` hidden dirs
- When a bookmark moves to a new folder, its image assets move too
- Keeps everything self-contained — copy a folder and you get everything

**4. Filename = sanitized title**
- `sanitize(title)` produces a valid macOS filename (no `/`, `:`, max 255 chars)
- Collision handling: append ` (2)`, ` (3)`, etc.
- UUID stays in SQLite, not the filename (human-readable filenames)

**5. Browser bookmark export is explicit**
- Netscape HTML is generated only by import/export flows
- It is not part of the live storage cycle

### Migration Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Add `relativePath` to Bookmark model (`decodeIfPresent` + nil fallback) | Complete |
| 2 | `BookmarkFileService.swift` — per-file I/O for `.webloc` artifacts plus legacy sidecar cleanup/backfill helpers | Complete |
| 3 | Service writes `.webloc` artifacts while SQLite remains canonical for metadata | Complete |
| 4 | One-time migration on first launch (`runBookmarkFileMigrationIfNeeded()`) — creates vault directories, writes `.webloc` artifacts, sets `didMigrateBookmarkFiles` flag | Complete |
| 5 | Reconcile `.webloc` artifacts — adopt new files, update tracked URLs, and prune missing files | Complete |
| 6 | Clean up — remove monolithic JSON write path and make bookmark index cache-only | Complete |

After migration, service-layer writes keep SQLite metadata and `.webloc` artifacts in sync. `_cider_bookmarks_index.json` is cache-only output, not an external edit API. Image assets stay in `.cider/bookmarks/.thumbnails/` and `.originals/` for now.

### What Changes for Users

- Bookmarks appear in Finder as .webloc files in organized folders
- Drag a URL from any browser into a Cider folder creates a bookmark
- Move bookmarks in Finder and Cider picks up the change (once Phase 5 ships)
- AI sorting becomes just file movement, instantly visible
- Everything else unchanged — same UI, same cards, same enrichment

### Risks & Mitigations

- **Filename collisions** — multiple bookmarks with same title. Mitigation: append ` (2)` etc.
- **Large folder scans** — scanning 1000+ `.webloc` files on load. Mitigation: SQLite path tracking and bookmark index caching reduce full rescans.
- **Artifact/metadata drift** — `.webloc` files and SQLite can diverge if writes bypass services. Mitigation: service-layer writes stay canonical and legacy sidecars no longer mask drift.
- **Image asset movement** — moving a bookmark between folders must also move thumbnails. Must be transactional.

---

## Appendix: Bookmark Storage System Audit

**Date:** 2026-03-23
**Purpose:** Blueprint for replacing BookmarksStorage with file-based VaultBookmarkService

### The Problem

`VaultBookmarkService` is the active bookmark runtime path. It loads bookmark metadata from SQLite, treats `.webloc` files as durable URL artifacts, and writes `_cider_bookmarks_index.json` only as a performance cache. Agents and automation should use `cider-cli` or app services for bookmark mutations rather than editing cache JSON.

### Current Load Path

1. Read SQLite bookmark metadata first
2. Reconcile missing/deleted `.webloc` artifacts
3. Adopt externally added `.webloc` files as new bookmarks
4. Write `_cider_bookmarks_index.json` as cache-only output

### Current Write Path (persist)

1. Write SQLite metadata
2. Write or update `.webloc` artifacts when the URL/file location changes
3. Write `_cider_bookmarks_index.json` as cache-only output
4. Push to SyncService

### Known Bugs

1. **URL-based dedup in adoption** — duplicate bookmarks with the same URL are not adopted as separate live bookmarks; duplicate files are left on disk instead of deleted.
2. **Thumbnail paths centralized** — bookmark media assets still resolve under `.cider/bookmarks/`.

### Files the Current System Reads

| File | Path | When |
|------|------|------|
| SQLite `cider.db` | `.cider/` | On load and metadata queries |
| `.webloc` files | vault folders | Artifact reconciliation and orphan adoption |
| `_cider_bookmarks.json` sidecars | per-folder | One-time legacy import only |

### Files the Current System Writes

| File | Path | When |
|------|------|------|
| SQLite `cider.db` | `.cider/` | Every bookmark metadata mutation |
| `_cider_bookmarks_index.json` | `.cider/bookmarks/` | Cache-only output after service mutations |
| `.webloc` plist files | vault folders | Bookmark create, URL update, restore, sync add, or repair |
| `_cider_bookmarks.json` sidecars | per-folder | No longer written; only read during one-time legacy import |
| `.thumbnails/<UUID>.png` | `.cider/bookmarks/.thumbnails/` | Enrichment |
| `.originals/<UUID>.<ext>` | `.cider/bookmarks/.originals/` | Enrichment |

### Public API to Replicate

#### CRUD
- `add(urlString:title:) -> Bookmark?`
- `addImageBookmark(title:) -> Bookmark`
- `addFromPasteboard() -> Bookmark?`
- `remove(_ bookmark:) -> TrashItem`
- `removeAll(_ bookmarks:) -> [TrashItem]`
- `restoreFromTrash(_ bookmark:)`
- `updateDetails(for:title:notes:tags:labelIDs:urlString:) -> Bool`
- `updateURL(for:urlString:)`
- `assignBookmark(_:toFolder:) -> Bool` — **MUST move .webloc file**

#### Labels
- `assignLabel(_:labelID:) -> Bool`
- `removeLabel(_:labelID:) -> Bool`
- `removeLabelsFromAll(labelID:)`

#### Thumbnails/Media
- `assignThumbnail(for:fromDroppedString:) async -> Bool`
- `assignThumbnail(for:fromLocalFileURL:) -> Bool`
- `assignThumbnail(for:imageData:preferredFileExtension:) -> Bool`
- `setReaderUnavailable(_:for:)`
- `setPreferredHeroMode(_:for:)`
- `setMediaType(_:for:)`
- `applyAIResults(...)`
- `refetchMetadata(for:)`

#### Sync
- `addFromSync(...)`
- `updateFromSync(...)`
- `removeSynced(_:)`
- `trashFromSync(_:)`

#### Folders (delegate to VaultFolderService — no legacy)
- No more `createFolder`, `renameFolder`, `deleteFolder` — use VaultFolderService

#### Import/Export
- `importNetscapeHTML(from:) -> Int`
- `exportNetscapeHTML(to:)`

#### Other
- `reloadFromDisk()`
- `updateDirectory(to:)`
- `adoptOrphanedVaultFiles()`
- `previewNormalizedURLString(from:) -> String?`

### Former BookmarksStorage Consumer List

This section used to track the migration off `BookmarksStorage.shared`. Runtime consumers now use `VaultBookmarkService`; direct `BookmarksStorage.shared` use is limited to the retired legacy storage implementation and historical docs.

### Current VaultBookmarkService Duties

1. **Load from SQLite** — use the database as canonical bookmark metadata
2. **Adopt files** — scan vault folders for externally added or moved `.webloc` artifacts
3. **Backfill legacy metadata once** — import `_cider_bookmarks.json` sidecars only during the guarded migration path
4. **Performance cache** — write `_cider_bookmarks_index.json` as cache-only output
5. **Move files on folder assign** — call `BookmarkFileService.move()`
6. **No legacy folders** — use `VaultFolderService` exclusively
7. **No monolithic JSON** — do not read or write `_cider_bookmarks_metadata.json`; browser `bookmarks.html` is explicit import/export only
8. **Proper trash** — move `.webloc` plus all bookmark assets
9. **Agent contract** — tell agents to use `cider-cli`/services, not cache JSON
