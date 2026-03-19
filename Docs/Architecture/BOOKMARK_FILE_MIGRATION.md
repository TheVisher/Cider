# Bookmark File Migration: Monolithic JSON → Individual .webloc Files

> **Status:** Phase 1-4 Implemented (dual-write)
> **Branch:** `bookmark-file-migration`
> **Goal:** Each bookmark becomes an individual `.webloc` file in the vault folder tree, with sidecar metadata. Folders are real directories. AI sorting becomes simple file movement.

---

## Current Architecture (what we're replacing)

- **One giant JSON** (`_cider_bookmarks_metadata.json`) holds ALL bookmarks + ALL folder definitions
- **Folders in JSON** are virtual — UUIDs in an array, not directories on disk
- **Sidebar folders** come from `VaultFolderService` (actual directories), creating a two-system disconnect
- **Thumbnails** live in hidden dirs: `.thumbnails/<UUID>.png`, `.originals/<UUID>.<ext>`
- **`bookmarks.html`** (Netscape format) written alongside JSON for browser import/export compatibility
- Every mutation rewrites both files atomically

## Target Architecture

```
~/CiderVault/
├── Bookmarks/                          ← unfiled bookmarks live here
│   ├── .cider-meta.json               ← metadata for items in this folder
│   ├── YouTube - Some Video.webloc
│   └── Reddit - Front Page.webloc
├── Entertainment/                      ← user folder (real directory)
│   ├── .cider-meta.json
│   ├── .thumbnails/                   ← thumbnails for items in this folder
│   │   └── <UUID>.png
│   ├── .originals/                    ← full-size images
│   │   └── <UUID>.jpg
│   ├── Netflix - A Show.webloc
│   └── Videos/                        ← sub-folder
│       ├── .cider-meta.json
│       └── TikTok - Funny Clip.webloc
├── Shopping/
│   ├── .cider-meta.json
│   ├── Amazon - Keyboard.webloc
│   └── Electronics/
│       └── ...
└── Notes/
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
- `sanitize(title)` → valid macOS filename (no `/`, `:`, max 255 chars)
- Collision handling: append ` (2)`, ` (3)`, etc.
- UUID stays in the sidecar metadata, not the filename (human-readable filenames)

**5. `bookmarks.html` still generated**
- Written to vault root on demand (export feature)
- Not part of the live storage cycle — just for browser import/export

---

## Migration Plan

### Phase 1: Add `relativePath` to Bookmark model ✅
- Added `relativePath: String?` to `Bookmark` (CodingKeys, init, decoder)
- Decode with `decodeIfPresent` + nil fallback for backward compat

### Phase 2: BookmarkFileService ✅
- New `BookmarkFileService.swift` handles per-file I/O
- `write(bookmark:toDirectory:)` — creates .webloc + updates sidecar
- `read(filename:from:)` / `readAll(from:)` — reads .webloc + sidecar metadata
- `move(bookmark:from:to:)` — moves .webloc + image assets + updates sidecars
- `delete(filename:from:)` — removes .webloc + image assets + sidecar cleanup
- Filename sanitization + collision handling (` (2)`, ` (3)`, etc.)
- Per-folder `_cider_bookmarks.json` sidecar with full Cider metadata

### Phase 3+4: Dual-write + One-time migration ✅
- `persist()` now dual-writes: monolithic JSON (existing) + .webloc files + sidecars (new)
- `runBookmarkFileMigrationIfNeeded()` runs on first launch:
  - Creates vault directories for legacy folders
  - Writes .webloc for each bookmark in the correct directory
  - Writes per-folder sidecar JSON
  - Sets `didMigrateBookmarkFiles` flag in CiderConfig
- After migration, every `persist()` call keeps files in sync
- Monolithic JSON stays as primary load source (safe fallback)
- Image assets stay in `Bookmarks/.thumbnails/` and `.originals/` for now

### Phase 5: Wire up FSEvents for live folder watching
- VaultFolderService already watches directories
- Extend to detect new .webloc files dropped in (drag from browser/Finder)
- Auto-enrich new bookmarks (fetch title, thumbnail, tags)
- Detect moved/deleted files and update state

### Phase 6: Clean up
- Remove monolithic JSON write path from BookmarksStorage
- Remove legacy `Folder` model from JSON (folders are directories now)
- Update VaultIndexService to use real file paths
- Update AI Chat CLAUDE.md — AI can now sort by moving files

---

## What Changes for Users

- **Bookmarks appear in Finder** as .webloc files in organized folders
- **Drag a URL from any browser into a Cider folder** → bookmark created
- **Move bookmarks in Finder** → Cider picks up the change
- **AI sorting** → just file movement, instantly visible
- **Everything else unchanged** — same UI, same cards, same enrichment

## What Stays the Same

- All existing bookmark data preserved (tags, thumbnails, AI data, notes, labels)
- Enrichment pipeline unchanged
- Card views, detail views, search — all unchanged
- Import/export via Netscape HTML still works

## Risks

- **Filename collisions** — multiple bookmarks with same title. Mitigation: append ` (2)` etc.
- **Large folder scans** — scanning 1000+ .webloc files on load. Mitigation: sidecar JSON is the fast path, .webloc files only read when sidecar is missing.
- **Atomic saves** — sidecar must be written atomically to avoid corruption. Use `.atomic` write option.
- **Image asset movement** — moving a bookmark between folders must also move thumbnails. Must be transactional.
