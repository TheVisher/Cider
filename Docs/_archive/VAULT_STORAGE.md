# Vault Storage Structure

All app-internal data lives inside `~/CiderVault/.cider/`, a hidden directory that macOS auto-hides from Finder. The vault root is reserved for user-visible folders only.

## Directory Layout

```
~/CiderVault/
├── .cider/                  ← ALL app internals (hidden by macOS)
│   ├── bookmarks/           ← Bookmark JSON files + metadata sidecar
│   ├── notes/               ← Note JSON files (title + HTML content)
│   ├── contacts/            ← Contact cards (JSON)
│   ├── date-cards/          ← Calendar-linked cards (JSON)
│   ├── labels/              ← Label definitions (JSON)
│   ├── saved-views/         ← Saved filter/sort configs (JSON)
│   ├── sources/             ← Linked source definitions (JSON)
│   ├── stacks/              ← Grouped collections (JSON)
│   ├── tags/                ← Tag definitions (JSON)
│   ├── todos/               ← Task items (JSON)
│   ├── clipboard/           ← Clipboard history (JSON)
│   ├── whiteboards/         ← Freeform canvas boards
│   ├── folders/             ← Folder metadata: index.json, covers/, .trash/
│   ├── ai-chat/             ← AI Chat conversation history per model
│   ├── ai/                  ← NL embedding vectors (embeddings.json)
│   └── index.json           ← Vault-wide item index
├── CLAUDE.md                ← AI tool instructions (must be at root)
├── Unsorted/                ← Default folder for uncategorized files
└── <User Folders>/          ← User-created, shown in sidebar
```

## How Paths Resolve

`StoragePaths.directoryURL(for:)` builds paths as:

```
vaultRoot/.cider/{StorageType.ciderSubpath}
```

The `ciderSubpath` property on `StorageType` maps each case to a lowercase, hyphenated name (e.g. `.dateCards` → `"date-cards"`, `.savedViews` → `"saved-views"`).

If a user has set a `directoryOverrides` entry in CiderConfig for a StorageType, that override takes precedence (absolute path).

## Migration

On first launch after the update, `VaultStructureMigration.migrateIfNeeded()` runs:

1. Creates `.cider/` directory
2. Moves each old top-level directory to its new location inside `.cider/`
3. Moves `.cider-index.json` → `.cider/index.json`
4. Moves `.cider-folders/` → `.cider/folders/`
5. Moves `AI Chat/` → `.cider/ai-chat/`
6. Moves `.ai/` → `.cider/ai/`
7. Sets `didMigrateVaultToCiderDir` flag in CiderConfig

The migration is idempotent — skips sources that don't exist or destinations that already exist.

## Why `.cider/`?

- macOS hides dotfiles from Finder by default → zero filtering code needed
- The vault root becomes purely user content
- VaultFolderService no longer needs a hardcoded list of internal directory names
- Adding new internal directories requires no code changes to filtering logic
