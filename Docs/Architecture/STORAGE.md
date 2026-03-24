# Storage Standard

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
├── claude-sessions/     # Claude Code agent session data
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

## Future: File Watching (External Edit Detection)

Currently, if a user (or an external tool like Apple Contacts or a text editor) modifies a `.vcf`, `.ics`, or `.md` file on disk, Cider won't notice until the next app restart. The in-memory state and the file can drift apart.

**Goal:** Use macOS `FSEvents` or `DispatchSource` to watch content directories (`Inbox/{Type}/` and user folders) for changes. When a file is created, modified, or deleted externally, the relevant storage service should detect it and reload.

**What this enables:**
- Edit a `.vcf` in Apple Contacts → Cider updates instantly
- AI tool creates a new `.ics` in the vault → appears in Cider without restart
- User deletes a file in Finder → card disappears from Cider
- True "filesystem is the source of truth" behavior

**Implementation notes:**
- The vault vision doc (`Docs/VAULT_VISION.md`) already describes FSEvents integration
- Debounce rapid changes (file saves trigger multiple events)
- Compare file modification dates against index `updatedAt` to detect actual changes
- Orphan adoption already handles "new file appeared" — file watching just triggers it live

### Vault File Adoption (Live)

`BookmarksStorage.adoptOrphanedVaultFiles()` runs on every load (debounced to at most once per 5 seconds). It scans all vault folders (including `Inbox/Bookmarks/`) for `.webloc` files not already tracked in the bookmarks array. Orphaned files are adopted as new bookmarks with the correct `folderID` based on their directory location. Files that have moved between folders also get their `folderID` updated. This means files created by agents, Finder drag-and-drop, or any external tool are picked up automatically.

### Webloc Cleanup on Trash

When a bookmark is trashed, `BookmarksStorage.deleteWeblocFile(for:)` deletes the corresponding `.webloc` file from the vault directory. This prevents the adoption scan from re-creating the bookmark on next load. The bookmark's metadata is still moved to `.cider/bookmarks/.trash/` as usual for potential restore.

---

## Bookmark File Migration (Monolithic JSON → Individual .webloc Files)

> **Status:** Phases 1-4 complete (dual-write active). Phases 5-6 are future work.

### Rationale

The original bookmark storage used a single monolithic JSON file (`_cider_bookmarks_metadata.json`) for ALL bookmarks and folder definitions. Folders were virtual (UUIDs in an array, not directories on disk), creating a disconnect with `VaultFolderService` which uses actual directories. The migration moves each bookmark to an individual `.webloc` file in the vault folder tree, with sidecar metadata. Folders become real directories. AI sorting becomes simple file movement.

### Target Architecture

```
~/CiderVault/
├── Bookmarks/                          # unfiled bookmarks live here
│   ├── .cider-meta.json               # metadata for items in this folder
│   ├── YouTube - Some Video.webloc
│   └── Reddit - Front Page.webloc
├── Entertainment/                      # user folder (real directory)
│   ├── .cider-meta.json
│   ├── .thumbnails/                   # thumbnails for items in this folder
│   │   └── <UUID>.png
│   ├── .originals/                    # full-size images
│   │   └── <UUID>.jpg
│   ├── Netflix - A Show.webloc
│   └── Videos/                        # sub-folder
│       ├── .cider-meta.json
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

**2. Per-folder `.cider-meta.json` sidecar**
- Maps each filename to its Cider metadata (tags, AI summary, colors, notes, labels, dates, etc.)
- One file per folder, not one per bookmark (avoids 2x file count)
- Structure:
```json
{
  "items": {
    "YouTube - Some Video.webloc": {
      "id": "UUID",
      "title": "YouTube - Some Video",
      "tags": ["entertainment", "video"],
      "labelIDs": ["UUID"],
      "aiSummary": "...",
      "dominantColors": ["#ff0000"],
      "thumbnailFilename": "<UUID>.png",
      "originalImageFilename": "<UUID>.jpg",
      "carouselImageFilenames": [],
      "notes": "",
      "createdAt": "2026-03-10T...",
      "updatedAt": "2026-03-10T...",
      "metadataUpdatedAt": "2026-03-10T...",
      "mediaType": "image",
      "dismissedLabelIDs": [],
      "ocrText": null,
      "readerUnavailable": false,
      "preferredHeroMode": "thumbnail"
    }
  }
}
```

**3. Thumbnails/originals move with bookmarks**
- Each folder has its own `.thumbnails/` and `.originals/` hidden dirs
- When a bookmark moves to a new folder, its image assets move too
- Keeps everything self-contained — copy a folder and you get everything

**4. Filename = sanitized title**
- `sanitize(title)` produces a valid macOS filename (no `/`, `:`, max 255 chars)
- Collision handling: append ` (2)`, ` (3)`, etc.
- UUID stays in the sidecar metadata, not the filename (human-readable filenames)

**5. `bookmarks.html` still generated**
- Written to vault root on demand (export feature)
- Not part of the live storage cycle — just for browser import/export

### Migration Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Add `relativePath` to Bookmark model (`decodeIfPresent` + nil fallback) | Complete |
| 2 | `BookmarkFileService.swift` — per-file I/O (write/read/move/delete .webloc + sidecar) | Complete |
| 3 | Dual-write in `persist()` — monolithic JSON (existing) + .webloc files + sidecars (new) | Complete |
| 4 | One-time migration on first launch (`runBookmarkFileMigrationIfNeeded()`) — creates vault directories, writes .webloc per bookmark, writes per-folder sidecar JSON, sets `didMigrateBookmarkFiles` flag | Complete |
| 5 | Wire up FSEvents for live folder watching — detect new .webloc files dropped in, auto-enrich, detect moved/deleted files | Future |
| 6 | Clean up — remove monolithic JSON write path, remove legacy `Folder` model from JSON, update VaultIndexService to use real file paths, update AI Chat CLAUDE.md | Future |

After migration, every `persist()` call keeps files in sync. Monolithic JSON stays as primary load source (safe fallback). Image assets stay in `Bookmarks/.thumbnails/` and `.originals/` for now.

### What Changes for Users

- Bookmarks appear in Finder as .webloc files in organized folders
- Drag a URL from any browser into a Cider folder creates a bookmark
- Move bookmarks in Finder and Cider picks up the change (once Phase 5 ships)
- AI sorting becomes just file movement, instantly visible
- Everything else unchanged — same UI, same cards, same enrichment

### Risks & Mitigations

- **Filename collisions** — multiple bookmarks with same title. Mitigation: append ` (2)` etc.
- **Large folder scans** — scanning 1000+ .webloc files on load. Mitigation: sidecar JSON is the fast path, .webloc files only read when sidecar is missing.
- **Atomic saves** — sidecar must be written atomically to avoid corruption. Use `.atomic` write option.
- **Image asset movement** — moving a bookmark between folders must also move thumbnails. Must be transactional.
