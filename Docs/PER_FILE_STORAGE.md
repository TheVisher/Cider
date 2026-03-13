# Per-File Storage Standard

This is the definitive reference for how Cider stores card data on disk. **Every card type** must follow this pattern. No exceptions.

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
