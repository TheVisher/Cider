# Sidecar Retirement Plan

**Status:** Working plan  
**Date:** 2026-04-15

## Goal

Remove sidecars as a permanent architecture pattern while preserving Cider's core promise:

- user content lives as real files in the vault
- SQLite provides the metadata, query, and agent-facing view of that content

This plan is intentionally phased. We do not delete sidecars until their responsibilities have an explicit SQLite replacement and a migration path for existing data.

## Current Audit

### 1. Bookmark sidecars are now one-time migration input

Primary code:

- `Sources/Cider/Services/BookmarkFileService.swift`
- `Sources/Cider/Services/VaultBookmarkService.swift`

Current sidecar:

- per-folder `_cider_bookmarks.json`

What it stores today:

- stable bookmark UUID
- title
- created/updated timestamps
- notes
- tags
- `labelIDs`
- `dismissedLabelIDs`
- AI summary
- OCR text
- dominant colors
- media type
- thumbnail/original image references
- carousel image references
- reader availability state
- preferred hero mode

Current risk:

- removing bookmark sidecars before the one-time import runs would strand some metadata in older vaults
- `.webloc` alone only carries the URL

Replacement path:

- move all bookmark metadata and stable identity into SQLite
- keep `.webloc` as the artifact
- reconcile moved/renamed files using SQLite path tracking plus artifact discovery
- import any remaining legacy sidecar metadata once, then stop consulting sidecars during normal load

Removal status:

- normal runtime reads no longer depend on bookmark sidecars
- one-time legacy import still exists for older vaults

### 2. Note sidecars are retired from runtime

Primary code:

- `Sources/Cider/Services/NotesStorage.swift`
- `Sources/Cider/Views/Notes/NoteCardView.swift`
- `Sources/Cider/Views/Notes/NoteListRow.swift`

Current sidecar:

- per-directory `.cider-meta.json`

What it stores today for notes:

- derived tag display
- summary display

Current risk:

- any leftover note-only metadata that still exists only in legacy sidecars is now intentionally abandoned
- stale `.cider-meta.json` files may still exist on disk until cleanup tooling removes them

Replacement path:

- keep note content and metadata in `.md` plus SQLite only
- remove obsolete `.cider-meta.json` files during final cleanup

Removal status:

- note sidecar reads and writes have been removed from runtime
- remaining work is deleting obsolete files from existing vaults

### 3. Generic sidecar support has been removed

Primary code:

- no generic sidecar service remains in the app runtime

Current behavior:

- no generic `.cider-meta.json` reader remains in normal runtime

Current risk:

- old sidecar files may still be present in user vaults until cleanup tooling removes them

Replacement path:

- treat any remaining sidecars as removable legacy files, not data sources

Removal status:

- completed in runtime
- remaining work is cleanup tooling and user messaging

### 4. Migration/export tooling still has sidecar-era assumptions in docs and helpers

Primary code:

- `Sources/Cider/Services/VaultMigrationService.swift`
- settings copy describing export behavior

Current behavior:

- exports `.webloc` files without recreating bookmark, note, or todo sidecars

Current risk:

- docs and helper text can still encode sidecars as part of the intended storage design

Replacement path:

- update migration/export to treat SQLite backup/export separately from artifact export
- stop generating sidecars as the default portable form

Removal status:

- runtime export behavior is aligned; remaining work is doc/helper cleanup

### 5. Docs still describe a conflicting hybrid model

Primary docs:

- `Docs/Architecture/STORAGE.md`
- `Docs/superpowers/specs/2026-04-09-sqlite-migration-design.md`

Current conflict:

- docs say files are source of truth
- code is increasingly SQLite-canonical for metadata
- some migration docs still assume sidecars are part of identity recovery

Replacement path:

- keep a single active doctrine
- treat older docs as historical/transitional unless updated

Removal status:

- can be fixed immediately

## Migration Strategy

### Phase 0: Lock the architecture

Deliverables:

- storage doctrine
- sidecar retirement plan
- clear statement that SQLite is canonical for metadata

Exit criteria:

- no new work introduces sidecars as a permanent dependency

### Phase 1: Harden SQLite before deeper cutover

Deliverables:

- rolling database backups
- pre-migration database snapshots
- integrity check support
- restore path
- audit logging for destructive mutations

Why first:

- once sidecars stop carrying metadata, SQLite becomes a larger failure domain

Exit criteria:

- metadata loss is mitigated by backup and restore tooling

### Phase 2: Make SQLite canonical for all new writes

Deliverables:

- every item type writes current metadata into SQLite
- service-layer mutations become the only supported write path
- agent and CLI mutations use the same storage services as the app

Exit criteria:

- new edits do not require sidecars to persist metadata

### Phase 3: Backfill existing sidecar metadata into SQLite

Deliverables:

- importer for bookmark sidecar metadata into SQLite
- importer for note sidecar metadata into SQLite
- verification pass to confirm parity after import

Exit criteria:

- sidecar-backed metadata exists in SQLite for current vaults

### Phase 4: Switch reads away from sidecars

Order:

1. notes
2. bookmark sidecar readers

Exit criteria:

- normal reads no longer depend on sidecars
  Status: completed for notes and for normal bookmark runtime; only one-time bookmark import remains

### Phase 5: Remove sidecar writes

Deliverables:

- stop writing note sidecars
  Status: completed for normal runtime and migration export
- stop writing bookmark sidecars
- stop writing todo sidecars
- stop using sidecars in migration/export flows
  Status: bookmark, note, and todo export paths no longer regenerate their legacy sidecars

Exit criteria:

- sidecars are no longer generated by normal app behavior

### Phase 6: Delete legacy sidecars

Deliverables:

- cleanup tool or one-time migration to remove obsolete sidecar files
- safe messaging to users about what is being removed

Exit criteria:

- no runtime dependency on per-item or per-folder sidecars remains

## Recommended First Implementation Slice

Start with note sidecars, not bookmarks.

Why:

- notes already have strong content artifacts in `.md`
- the remaining note sidecar responsibilities are narrower
- note UI can be redirected to SQLite-backed metadata without redesigning the bookmark stack

First concrete tasks:

1. add any missing note metadata fields to SQLite
2. migrate note sidecar metadata into SQLite
3. update note card/list UI to read that metadata from SQLite-backed state
4. remove note UUID recovery dependence on sidecars
5. remove the last note-sidecar runtime reads

## Bookmark-Specific Warning

Bookmarks are the highest-risk sidecar removal.

A `.webloc` artifact gives us:

- URL

It does not natively give us:

- title override
- notes
- tags
- labels
- summaries
- OCR text
- image references
- stable bookmark identity

That is fine in the target model because SQLite will own that metadata, but it means bookmark sidecars cannot be removed until SQLite fully covers the read and rebuild path Cider expects.

## Success Criteria

We are done when all of the following are true:

- Cider can render rich cards without reading sidecars
- new metadata is persisted in SQLite only
- agent and CLI writes go through storage services
- sidecars are unnecessary for launch-time reconciliation
- backup and restore exist for the SQLite metadata layer
